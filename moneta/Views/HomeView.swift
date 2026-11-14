import SwiftUI

struct HomeView: View {
    @Environment(MonetaStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        let count = typeSize >= .accessibility1 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Metrics.spacing, alignment: .top), count: count)
    }

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let warning = store.latestWarning {
                        NavigationLink(value: Route.signal(warning.id)) {
                            LatestWarningCard(signal: warning, reaction: store.reaction(to: warning),
                                              isFresh: store.freshIDs.contains(warning.id))
                        }
                        .buttonStyle(PressableStyle())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else if !store.isLoaded {
                        ProgressView().tint(Palette.amber).frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        Card {
                            Label {
                                Text("No high signals right now. Moneta shows the next one here the moment the web moves.")
                                    .font(.mCallout)
                                    .foregroundStyle(Palette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "eye").foregroundStyle(Palette.amber)
                            }
                        }
                    }

                    if let message = store.errorMessage {
                        Card(fill: Palette.tint(Palette.down), border: Palette.down.opacity(0.4)) {
                            HStack(alignment: .top, spacing: 10) {
                                Text(message)
                                    .font(.mFootnote)
                                    .foregroundStyle(Palette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Button {
                                    store.errorMessage = nil
                                } label: {
                                    Image(systemName: "xmark").frame(width: 44, height: 44)
                                }
                                .foregroundStyle(Palette.secondary)
                                .accessibilityLabel("Dismiss")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Metrics.spacing) {
                        SectionTitle(text: "Your stocks", trailing: "\(store.watched.count) watching")
                        LazyVGrid(columns: columns, spacing: Metrics.spacing) {
                            ForEach(store.watched) { company in
                                NavigationLink(value: Route.stock(company.ticker)) {
                                    StockTile(
                                        company: company,
                                        quote: store.quotes[company.ticker],
                                        points: store.intraday[company.ticker] ?? [],
                                        newCount: store.newCount(for: company.ticker)
                                    )
                                }
                                .buttonStyle(PressableStyle())
                            }
                            Button {
                                router.addStock = AddStockTarget(company: nil)
                            } label: {
                                AddStockTile()
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Add stock")
                        }
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: store.latestWarning?.id)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: store.watched.map(\.ticker))
            }
            .monetaScreen()
            .toolbar(.hidden, for: .navigationBar)
            .monetaDestinations()
        }
        #if DEBUG
        .onChange(of: router.pending) { _, route in
            guard let route else { return }
            router.pending = nil
            switch route {
            case "stock": if let first = store.watched.first { path.append(Route.stock(first.ticker)) }
            case "signal":
                if let signal = store.latestWarning ?? store.signals.first { path.append(Route.signal(signal.id)) }
            case "signalLow":
                if let signal = store.signals.first(where: { $0.ticker == "VNTR" && $0.impact == .low }) { path.append(Route.signal(signal.id)) }
            default: break
            }
        }
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.background)
                .frame(width: 44, height: 44)
                .background(Palette.amber, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Moneta")
                    .font(.mTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    LiveDot()
                    Text("Live · watching \(store.watched.count) \(store.watched.count == 1 ? "company" : "companies")")
                        .font(.mFootnote)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 8)
            IconButton(systemImage: "bell", label: "Signals") {
                router.tab = .signals
            }
        }
    }
}

/// Pulsing green dot for "Live".
struct LiveDot: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(Palette.up.opacity(0.35))
                .frame(width: 14, height: 14)
                .scaleEffect(pulse ? 1.2 : 0.4)
                .opacity(pulse ? 0 : 1)
            Circle().fill(Palette.up).frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// The newest high-impact signal with its lead-time strip.
private struct LatestWarningCard: View {
    let signal: Signal
    let reaction: MarketReaction?
    let isFresh: Bool

    var body: some View {
        Card(fill: Palette.card, border: Palette.amber.opacity(isFresh ? 0.9 : 0.35)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Latest warning")
                        .font(.mCaption)
                        .foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    ImpactTag(impact: signal.impact)
                }
                HStack(spacing: 6) {
                    Text(signal.ticker)
                        .font(.mSubheadline)
                        .foregroundStyle(Palette.amber)
                    Text("· \(Fmt.when(signal.time)) · \(signal.source.label)")
                        .font(.mFootnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Text(signal.title)
                    .font(.mTitle2)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    LeadTimeStrip(signalTime: signal.time, reaction: reaction)
                    Text(reaction?.leadMinutes.map { "Web \(Fmt.time(signal.time)) · \($0) min ahead of the market" } ?? "Web \(Fmt.time(signal.time)) · watching the market")
                        .font(.mFootnote)
                        .foregroundStyle(Palette.amber)
                }
            }
        }
        .overlay(
            RadialGradient(colors: [Palette.amber.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .allowsHitTesting(false)
        )
        .shadow(color: isFresh ? Palette.amber.opacity(0.3) : .clear, radius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the signal")
    }
}

#Preview {
    HomeView()
        .environment(MonetaStore.preview())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
