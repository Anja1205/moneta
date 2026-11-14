import Charts
import SwiftUI

struct SignalDetailView: View {
    let signalID: UUID
    @Environment(MonetaStore.self) private var store
    @State private var showingSource = false

    private var signal: Signal? { store.signals.first { $0.id == signalID } }

    var body: some View {
        Group {
            if let signal {
                content(signal)
            } else {
                ContentUnavailableView("Signal not found", systemImage: "eye.slash",
                                       description: Text("It may belong to a stock you stopped watching."))
            }
        }
        .monetaScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ signal: Signal) -> some View {
        let company = store.company(signal.ticker)
        let reaction = store.reaction(to: signal)
        let muted = store.isMuted(signal)

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Tags and headline
                VStack(alignment: .leading, spacing: 12) {
                    FlowLayout(spacing: 8) {
                        ImpactTag(impact: signal.impact)
                        CapsuleTag(signal.source.label, systemImage: signal.source.symbol)
                        CapsuleTag(Fmt.when(signal.time), systemImage: "clock", color: Palette.muted)
                    }
                    Text(signal.title)
                        .font(.mTitle)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let company {
                        Text("\(company.name) · \(company.ticker)")
                            .font(.mCallout)
                            .foregroundStyle(Palette.secondary)
                    }
                }

                whyCard(signal)
                if !signal.diff.isEmpty {
                    whatChanged(signal)
                }
                marketReaction(signal, reaction: reaction)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(signal.ticker)
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        store.toggleMute(signal)
                    } label: {
                        Label(muted ? "Unmute" : "Mute", systemImage: muted ? "bell" : "bell.slash")
                            .font(.mBodyStrong)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                    .accessibilityHint("Mutes \(signal.source.label.lowercased()) signals for \(signal.ticker)")

                    Button {
                        showingSource = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("Open source")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.mBodyStrong)
                        .foregroundStyle(Palette.background)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.amber)
                    .disabled(signal.url == nil)
                    .accessibilityHint(signal.url.map { "Opens \($0.host() ?? "the page") in Safari" } ?? "No link for this signal")
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 8)
        }
        .sensoryFeedback(.selection, trigger: muted) { _, _ in store.hapticsEnabled }
        .sheet(isPresented: $showingSource) {
            if let url = signal.url {
                SafariView(url: url).ignoresSafeArea()
            }
        }
        .onAppear { store.markSeen(signal) }
    }

    // MARK: Sections

    private func whyCard(_ signal: Signal) -> some View {
        Card(fill: Palette.tint(Palette.amber), border: Palette.amber.opacity(0.35)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.background)
                        .frame(width: 32, height: 32)
                        .background(Palette.amber, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why it matters")
                            .font(.mCaption)
                            .foregroundStyle(Palette.amber)
                        Text(signal.why)
                            .font(.mBodyStrong)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !signal.facts.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(signal.facts, id: \.self) { fact in
                            CapsuleTag(fact, systemImage: "checkmark.seal", color: Palette.text)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func whatChanged(_ signal: Signal) -> some View {
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            SectionTitle(text: "What changed")
            Card(padding: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(signal.diff) { line in
                        DiffRow(line: line)
                    }
                }
            }
        }
    }

    private func marketReaction(_ signal: Signal, reaction: MarketReaction?) -> some View {
        let series = store.intraday[signal.ticker] ?? []
        let window = series.filter {
            $0.date >= signal.time.addingTimeInterval(-30 * 60) && $0.date <= signal.time.addingTimeInterval(100 * 60)
        }
        return VStack(alignment: .leading, spacing: Metrics.spacing) {
            SectionTitle(text: "Market reaction")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text(reactionText(reaction))
                        .font(.mHeadline)
                        .monospacedDigit()
                        .foregroundStyle(reaction?.at != nil ? Palette.change(reaction?.move ?? 0) : Palette.secondary)
                    PriceChartView(points: window, signals: [signal], number: store.pinNumber(for:),
                                   reaction: store.reaction(to:), compact: true)
                        .frame(height: 140)
                }
            }
        }
    }

    private func reactionText(_ reaction: MarketReaction?) -> String {
        guard let reaction else { return "Waiting for prices" }
        if let minutes = reaction.leadMinutes {
            return "\(Fmt.percent(reaction.move)) · \(minutes) min later"
        }
        return reaction.settled ? "\(Fmt.percent(reaction.move)) · no real move" : "Watching the market…"
    }
}

/// One diff line: unchanged in grey, added in green with "+", removed in red with "−".
private struct DiffRow: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(marker)
                .font(.moneta(size: 15, weight: .bold, relativeTo: .callout))
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(line.text)
                .font(.mCallout)
                .strikethrough(line.kind == .removed, color: Palette.down.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibilityPrefix)\(line.text)")
    }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .unchanged: ""
        }
    }

    private var color: Color {
        switch line.kind {
        case .added: Palette.up
        case .removed: Palette.down
        case .unchanged: Palette.muted
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: Palette.tint(Palette.up)
        case .removed: Palette.tint(Palette.down)
        case .unchanged: .clear
        }
    }

    private var accessibilityPrefix: String {
        switch line.kind {
        case .added: "Added: "
        case .removed: "Removed: "
        case .unchanged: ""
        }
    }
}

#Preview {
    let store = MonetaStore.preview()
    NavigationStack {
        SignalDetailView(signalID: MockData.seeded[0].change.id)
    }
    .environment(store)
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
