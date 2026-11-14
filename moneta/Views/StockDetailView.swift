import Charts
import SwiftUI

struct StockDetailView: View {
    let ticker: String
    @Environment(MonetaStore.self) private var store
    @State private var range: ChartRange = .day
    @State private var history: [PricePoint] = []
    @State private var confirmingRemove = false
    @Environment(\.dismiss) private var dismiss

    private var company: Company? { store.company(ticker) }
    private var quote: Quote? { store.quotes[ticker] }
    private var signals: [Signal] { store.signals(for: ticker) }
    private var points: [PricePoint] { range == .day ? (store.intraday[ticker] ?? []) : history }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                priceHeader

                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        PriceChartView(
                            points: points,
                            signals: range == .day ? signals : [],
                            number: store.pinNumber(for:),
                            reaction: store.reaction(to:)
                        )
                        .frame(height: 250)
                        if range != .day, !signals.isEmpty {
                            Text("Signal pins show on the 1D chart.")
                                .font(.mFootnote)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }

                GlassSegmented(options: ChartRange.allCases, selection: $range, title: \.rawValue, accessibilityLabel: "Chart range")

                VStack(alignment: .leading, spacing: Metrics.spacing) {
                    SectionTitle(text: "Signal timeline", trailing: signals.isEmpty ? nil : "\(signals.count) recent")
                    if signals.isEmpty {
                        Card {
                            Text("No signals for \(company?.name ?? ticker) in the last few days. Moneta adds them here as soon as the web changes.")
                                .font(.mCallout)
                                .foregroundStyle(Palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(signals) { signal in
                        NavigationLink(value: Route.signal(signal.id)) {
                            SignalTimelineCard(
                                signal: signal,
                                number: store.pinNumber(for: signal),
                                reaction: store.reaction(to: signal),
                                isFresh: store.freshIDs.contains(signal.id),
                                isMuted: store.isMuted(signal)
                            )
                        }
                        .buttonStyle(PressableStyle())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: signals.map(\.id))
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .monetaScreen()
        .navigationTitle(company?.name ?? ticker)
        .navigationSubtitle(company?.tickerLine ?? ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let settings = store.settings[ticker] {
                        Picker("Alert me for", selection: Binding(
                            get: { settings.alertLevel },
                            set: { level in
                                var updated = settings
                                updated.alertLevel = level
                                Task { await store.updateSettings(ticker, updated) }
                            }
                        )) {
                            ForEach(AlertLevel.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    Divider()
                    Button("Stop watching", systemImage: "eye.slash", role: .destructive) { confirmingRemove = true }
                } label: {
                    Image(systemName: "bell.badge")
                }
                .accessibilityLabel("Alerts for \(ticker)")
            }
        }
        .confirmationDialog("Stop watching \(ticker)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Stop watching", role: .destructive) {
                Task {
                    await store.removeStock(ticker)
                    dismiss()
                }
            }
        } message: {
            Text("Its signals leave your timeline. You can add it again from Search.")
        }
        .task(id: range) {
            if range != .day { history = await store.history(ticker, range: range) }
        }
        .onAppear { store.markSeen(ticker) }
        .onChange(of: signals.count) { _, _ in store.markSeen(ticker) }
    }

    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let quote {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) { bigPrice(quote); ChangeCapsule(fraction: quote.changeFraction, large: true) }
                    VStack(alignment: .leading, spacing: 8) { bigPrice(quote); ChangeCapsule(fraction: quote.changeFraction, large: true) }
                }
                Text("\(Fmt.signedPrice(quote.change, currency: quote.currency)) today · \(signals.count) \(signals.count == 1 ? "signal" : "signals")")
                    .font(.mCallout)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
                    .contentTransition(.numericText(value: quote.change))
                    .animation(.snappy, value: quote.change)
            } else {
                Text("—").font(.mLargeTitle).foregroundStyle(Palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bigPrice(_ quote: Quote) -> some View {
        Text(Fmt.price(quote.price, currency: quote.currency))
            .font(.moneta(size: 40, weight: .bold, relativeTo: .largeTitle))
            .monospacedDigit()
            .foregroundStyle(Palette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText(value: quote.price))
            .animation(.snappy, value: quote.price)
    }
}

/// Price line with signal rules, numbered pins and the shaded lead-time band.
struct PriceChartView: View {
    let points: [PricePoint]
    let signals: [Signal]
    let number: (Signal) -> Int
    let reaction: (Signal) -> MarketReaction?
    var compact = false

    private var color: Color {
        guard let first = points.first?.price, let last = points.last?.price, first > 0 else { return Palette.muted }
        return Palette.change(last / first - 1)
    }

    private var priceRange: (low: Double, high: Double) {
        let prices = points.map(\.price)
        let low = prices.min() ?? 0, high = prices.max() ?? 1
        let pad = max((high - low) * 0.08, high * 0.001)
        return (low - pad, high + pad)
    }

    /// Room above the line for pins.
    private var domainTop: Double {
        let r = priceRange
        return signals.isEmpty ? r.high : r.high + (r.high - r.low) * 0.22
    }

    /// Signals in the chart's range, thinned so pins never pile up: most important (then newest)
    /// first, at most 8, each at least 7% of the range apart. The timeline below lists all of them.
    private var visibleSignals: [Signal] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        let inRange = signals.filter { $0.time >= first && $0.time <= last }
        guard inRange.count > 3 else { return inRange }
        let minGap = last.timeIntervalSince(first) * 0.07
        var picked: [Signal] = []
        for signal in inRange.sorted(by: { ($0.impact, $0.time) > ($1.impact, $1.time) }) {
            guard picked.count < 8 else { break }
            if picked.allSatisfy({ abs($0.time.timeIntervalSince(signal.time)) >= minGap }) {
                picked.append(signal)
            }
        }
        return picked
    }

    var body: some View {
        if points.count < 2 {
            VStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                Text(points.isEmpty ? "No prices for this range yet." : "The chart fills in as new prices arrive.")
                    .font(.mFootnote)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            chart
        }
    }

    private var chart: some View {
        let r = priceRange
        return Chart {
            ForEach(visibleSignals) { signal in
                if let reaction = reaction(signal), let at = reaction.at, let lead = reaction.leadMinutes, lead >= 3 {
                    RectangleMark(
                        xStart: .value("Signal", signal.time),
                        xEnd: .value("Move", at),
                        yStart: .value("Low", r.low),
                        yEnd: .value("High", r.high)
                    )
                    .foregroundStyle(Palette.amber.opacity(0.10))
                }
            }

            ForEach(points) { point in
                AreaMark(x: .value("Time", point.date), yStart: .value("Base", r.low), yEnd: .value("Price", point.price))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.date), y: .value("Price", point.price))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }

            ForEach(visibleSignals) { signal in
                RuleMark(x: .value("Signal", signal.time), yStart: .value("Low", r.low), yEnd: .value("Top", r.high))
                    .foregroundStyle(SignalPin.color(for: signal.impact))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    // Pin centred on the rule, with the lead time beside it in the band's direction.
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        let size: CGFloat = compact ? 18 : 22
                        HStack(spacing: 4) {
                            SignalPin(number: number(signal), impact: signal.impact, size: size)
                            if !compact, let lead = reaction(signal)?.leadMinutes, lead >= 3 {
                                Text("\(lead)m")
                                    .font(.mCaption)
                                    .monospacedDigit()
                                    .fixedSize()
                                    .foregroundStyle(Palette.amber)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.tint(Palette.amber), in: Capsule())
                                    .accessibilityLabel("\(lead) minutes ahead")
                            }
                        }
                        .offset(x: -size / 2)
                    }
            }
        }
        .chartYScale(domain: r.low...domainTop)
        .chartXScale(domain: (points.first?.date ?? .now)...(points.last?.date ?? .now))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: compact ? 2 : 4)) { value in
                AxisGridLine().foregroundStyle(Palette.border.opacity(0.6))
                AxisValueLabel {
                    if let price = value.as(Double.self), price <= r.high {
                        Text(Self.axisPrice(price))
                            .font(.mCaption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 3 : 4)) { value in
                AxisValueLabel(collisionResolution: .greedy) {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(date))
                            .font(.mCaption)
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .accessibilityLabel("Price chart")
        .accessibilityValue(accessibilitySummary)
    }

    private static func axisPrice(_ price: Double) -> String {
        let digits: ClosedRange<Int> = price < 10 ? 2...2 : 0...1
        return price.formatted(.number.precision(.fractionLength(digits)))
    }

    private func axisLabel(_ date: Date) -> String {
        guard let first = points.first?.date, let last = points.last?.date else { return "" }
        return last.timeIntervalSince(first) < 36 * 3600
            ? Fmt.time(date)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var accessibilitySummary: String {
        guard let first = points.first?.price, let last = points.last?.price, first > 0 else { return "" }
        var text = "\(Fmt.percent(last / first - 1)) over the period"
        if !visibleSignals.isEmpty { text += ", \(visibleSignals.count) signals marked" }
        return text
    }
}

#Preview {
    NavigationStack {
        StockDetailView(ticker: "VNTR")
    }
    .environment(MonetaStore.preview())
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
