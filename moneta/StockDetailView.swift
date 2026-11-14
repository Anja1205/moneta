import Charts
import SwiftUI

struct StockDetailView: View {
    let stock: Stock
    @Environment(SignalStore.self) private var store
    @State private var editingPosition = false

    /// Live copy so Realtime stock updates show here too.
    private var current: Stock { store.stocks.first { $0.id == stock.id } ?? stock }
    private var signals: [Signal] { store.signals(for: stock) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                header
                    .padding(.bottom, 8)
                PriceChart(stock: current, points: store.priceHistory[stock.id] ?? [], signals: signals)
                if let sentiment = store.sentiment[stock.id] {
                    SentimentCard(sentiment: sentiment)
                }
                PositionCard(stock: current, holding: store.holding(for: current)) { editingPosition = true }
                SignalChart(signals: signals)
                timeline
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .refreshable {
            await store.refreshAll()
            await store.load()
        }
        .demoScrollAnchor()
        .task(id: stock.id) {
            await store.loadPriceHistory(for: stock)
            #if DEBUG
            if DemoMode.isMain, DemoMode.screen == "position" { editingPosition = true }
            #endif
        }
        .sheet(isPresented: $editingPosition) {
            PositionEditor(stock: current, holding: store.holding(for: current))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
        .navigationTitle(current.ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LivePill(isLive: store.isLive)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                CompanyLogo(stock: current, size: .header)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(current.ticker)
                            .font(Theme.title)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if current.isDemo { DemoTag() }
                    }
                    Text(current.name)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                    Text(PriceFormat.money(current.price, currency: current.currencyCode))
                        .font(Theme.number(.largeTitle, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(current.price == nil ? Theme.textTertiary : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: current.price ?? 0))
                        .animation(.snappy, value: current.price)
                        .priceFlash(store.priceFlash[stock.id])
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { changeRow }
                        VStack(alignment: .leading, spacing: 6) { changeRow }
                    }
                    if let updated = current.priceUpdatedDate {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            HStack(spacing: 8) {
                                Text(RelativeTime.updated(updated, now: context.date))
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                                if current.isMarketClosed(now: context.date) {
                                    Label("Market closed", systemImage: "moon.zzz.fill")
                                        .font(Theme.caption.weight(.semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.06), in: Capsule())
                                }
                            }
                        }
                    } else if current.price == nil {
                        Text("No price yet. Tap refresh on the chart to fetch one.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
            }
            .background(alignment: .leading) {
                GoldGlow(width: 240, height: 110, intensity: 0.5)
                    .offset(x: -40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var changeRow: some View {
        if current.priceChange != nil {
            Text(PriceFormat.signedMoney(current.priceChange, currency: current.currencyCode))
                .font(Theme.number(.subheadline))
                .monospacedDigit()
                .foregroundStyle(Theme.color(for: current.priceDirection))
                .lineLimit(1)
                .contentTransition(.numericText(value: current.priceChange ?? 0))
        }
        if current.priceChangePct != nil {
            PriceChangePill(percent: current.priceChangePct, size: .regular)
        }
    }

    @ViewBuilder
    private var timeline: some View {
        Text("Timeline")
            .font(Theme.sectionTitle)
            .foregroundStyle(Theme.textPrimary)
            .padding(.top, 12)
            .accessibilityAddTraits(.isHeader)

        if signals.isEmpty {
            Text("No signals yet. Pull down to check the web now.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .card()
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                LazyVStack(spacing: 12) {
                    ForEach(signals) { signal in
                        NavigationLink(value: signal) {
                            SignalRow(
                                signal: signal,
                                isFresh: store.freshIds.contains(signal.id),
                                now: context.date
                            )
                        }
                        .buttonStyle(PressableCardStyle())
                        .transition(.signalInsert)
                    }
                }
                .animation(.signalSpring, value: signals.map(\.id))
            }
        }
    }
}

// MARK: - Chart

private struct SignalChart: View {
    let signals: [Signal]

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Int
        let direction: Direction
    }

    private var span: TimeInterval {
        let dates = points.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return 0 }
        return last.timeIntervalSince(first)
    }

    private var points: [Point] {
        signals.compactMap { signal in
            guard let date = signal.publishedDate ?? signal.detectedDate else { return nil }
            let value: Int
            switch signal.direction {
            case .bullish: value = signal.clampedImpact
            case .bearish: value = -signal.clampedImpact
            case .neutral: value = 0
            }
            return Point(id: signal.id, date: date, value: value, direction: signal.direction)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Signal pressure")

            if points.isEmpty {
                Text("The chart fills in as signals arrive.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Color.white.opacity(0.15))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    ForEach(points) { point in
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Impact", point.value),
                            width: .fixed(6)
                        )
                        .foregroundStyle(Theme.color(for: point.direction))
                        .cornerRadius(2)

                        // Neutral signals have zero height; mark them so they stay visible.
                        if point.value == 0 {
                            PointMark(x: .value("Date", point.date), y: .value("Impact", 0))
                                .symbolSize(28)
                                .foregroundStyle(Theme.neutral)
                        }
                    }
                }
                .chartYScale(domain: -5...5)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [-5, 0, 5]) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            switch value.as(Int.self) {
                            case 5: Text("Bullish").foregroundStyle(Theme.bullish)
                            case -5: Text("Bearish").foregroundStyle(Theme.bearish)
                            default: Text("")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                        AxisValueLabel(collisionResolution: .greedy) {
                            if let date = value.as(Date.self) {
                                Text(AxisDate.label(date, span: span))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Signals over time, bullish above the line, bearish below")
            }
        }
        .card()
    }
}

// MARK: - Price chart

private struct PriceChart: View {
    let stock: Stock
    let points: [PricePoint]
    let signals: [Signal]
    @Environment(SignalStore.self) private var store
    @State private var selectedID: UUID?

    private struct Sample: Identifiable {
        let id: UUID
        let date: Date
        let price: Double
    }

    /// A signal placed on the price line at its time.
    private struct Marker: Identifiable {
        let signal: Signal
        let date: Date
        let price: Double
        var id: UUID { signal.id }
    }

    private var samples: [Sample] {
        points
            .compactMap { point in point.date.map { Sample(id: point.id, date: $0, price: point.price) } }
            .sorted { $0.date < $1.date }
    }

    /// Signals inside the charted range, with the price interpolated at their time.
    private var markers: [Marker] {
        let samples = samples
        guard let first = samples.first, let last = samples.last, samples.count > 1 else { return [] }
        return signals.compactMap { signal in
            let date = signal.displayDate
            guard date >= first.date, date <= last.date else { return nil }
            guard let upper = samples.firstIndex(where: { $0.date >= date }) else { return nil }
            let after = samples[upper]
            guard upper > 0 else { return Marker(signal: signal, date: date, price: after.price) }
            let before = samples[upper - 1]
            let span = after.date.timeIntervalSince(before.date)
            let t = span > 0 ? date.timeIntervalSince(before.date) / span : 0
            return Marker(signal: signal, date: date, price: before.price + (after.price - before.price) * t)
        }
    }

    /// Green if the price is up over the charted period, red if down; today's move when flat.
    private var color: Color {
        if let first = samples.first?.price, let last = samples.last?.price, samples.count > 1, first != last {
            return last > first ? Theme.bullish : Theme.bearish
        }
        return Theme.color(for: stock.priceDirection)
    }

    private var periodChangePct: Double? {
        guard let first = samples.first?.price, let last = samples.last?.price, samples.count > 1, first != 0 else { return nil }
        return (last - first) / first * 100
    }

    private var span: TimeInterval {
        guard let first = samples.first?.date, let last = samples.last?.date else { return 0 }
        return last.timeIntervalSince(first)
    }

    private var yDomain: ClosedRange<Double> {
        let prices = samples.map(\.price)
        guard let low = prices.min(), let high = prices.max() else { return 0...1 }
        let pad = max((high - low) * 0.12, high * 0.002, 0.01)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionLabel("Price · 7 days")
                if let periodChangePct {
                    PriceChangePill(percent: periodChangePct)
                }
                Spacer(minLength: 4)
                Button {
                    Task { await store.refreshPrices(ticker: stock.ticker) }
                } label: {
                    if store.isRefreshingPrices {
                        ProgressView().controlSize(.small).tint(Theme.gold)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                    }
                }
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .buttonStyle(PressableButtonStyle())
                .disabled(store.isRefreshingPrices)
                .accessibilityLabel("Refresh price")
            }

            if samples.count < 2 {
                Text(samples.isEmpty ? "No price history yet. Tap refresh to fetch the latest price." : "The chart fills in as prices arrive.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart
                if !markers.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.gold).frame(width: 6, height: 6)
                        Text("\(markers.count) \(markers.count == 1 ? "signal" : "signals") on the chart. Tap a dot to read it.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .card()
        .sensoryFeedback(.selection, trigger: selectedID)
        #if DEBUG
        .task(id: points.count) {
            if DemoMode.isMain, DemoMode.screen == "callout", selectedID == nil {
                selectedID = markers.dropFirst().first?.id ?? markers.first?.id
            }
        }
        #endif
    }

    private var chart: some View {
        let markers = markers
        let selected = markers.first { $0.id == selectedID }
        return Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.date),
                    yStart: .value("Base", yDomain.lowerBound),
                    yEnd: .value("Price", sample.price)
                )
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)

                LineMark(x: .value("Time", sample.date), y: .value("Price", sample.price))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }

            if let selected {
                RuleMark(x: .value("Time", selected.date))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            ForEach(markers) { marker in
                let isSelected = marker.id == selectedID
                PointMark(x: .value("Time", marker.date), y: .value("Price", marker.price))
                    .symbol {
                        Circle()
                            .fill(Theme.color(for: marker.signal.direction))
                            .frame(width: isSelected ? 14 : 9, height: isSelected ? 14 : 9)
                            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                    }
                    .accessibilityLabel("\(marker.signal.direction.label) signal")
                    .accessibilityValue(marker.signal.title)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: (samples.first?.date ?? .now)...(samples.last?.date ?? .now))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(PriceFormat.axis(price))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel(collisionResolution: .greedy) {
                    if let date = value.as(Date.self) {
                        Text(AxisDate.label(date, span: span))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { tap in
                                select(near: tap.location, markers: markers, proxy: proxy, plot: plot)
                            }
                        )
                    if let selected, let point = proxy.position(for: (selected.date, selected.price)) {
                        callout(for: selected, at: CGPoint(x: plot.minX + point.x, y: plot.minY + point.y), in: geo.size)
                    }
                }
            }
        }
        .frame(height: 200)
        .animation(.snappy(duration: 0.25), value: selectedID)
        .animation(.easeInOut(duration: 0.4), value: samples.count)
        .accessibilityLabel("Price history for \(stock.ticker) over 7 days")
    }

    /// Selects the marker nearest the tap (within 30pt); a tap elsewhere clears the selection.
    private func select(near location: CGPoint, markers: [Marker], proxy: ChartProxy, plot: CGRect) {
        let nearest = markers
            .compactMap { marker -> (Marker, CGFloat)? in
                guard let p = proxy.position(for: (marker.date, marker.price)) else { return nil }
                let dx = plot.minX + p.x - location.x, dy = plot.minY + p.y - location.y
                return (marker, (dx * dx + dy * dy).squareRoot())
            }
            .min { $0.1 < $1.1 }
        if let nearest, nearest.1 <= 30 {
            selectedID = nearest.0.id == selectedID ? nil : nearest.0.id
        } else {
            selectedID = nil
        }
    }

    /// The selected signal, above the dot in the lower half of the chart, below it in the upper half.
    /// Placed with fixed frames rather than a measured height (measuring fed back into layout and looped).
    @ViewBuilder
    private func callout(for marker: Marker, at point: CGPoint, in size: CGSize) -> some View {
        let width = min(240, size.width - 8)
        let x = min(max(point.x - width / 2, 4), size.width - width - 4)
        let above = point.y >= size.height / 2
        if above {
            calloutCard(for: marker, width: width)
                .frame(width: width, height: max(point.y - 12, 0), alignment: .bottom)
                .offset(x: x)
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
        } else {
            calloutCard(for: marker, width: width)
                .frame(width: width, height: max(size.height - point.y - 12, 0), alignment: .top)
                .offset(x: x, y: point.y + 12)
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
        }
    }

    private func calloutCard(for marker: Marker, width: CGFloat) -> some View {
        NavigationLink(value: marker.signal) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    DirectionBadge(direction: marker.signal.direction)
                    Spacer(minLength: 4)
                    Text(marker.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Text(marker.signal.title)
                    .font(Theme.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text("Read signal")
                    Image(systemName: "chevron.right")
                }
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.gold)
            }
            .padding(10)
            .frame(width: width, alignment: .leading)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.color(for: marker.signal.direction).opacity(0.5))
            )
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityHint("Opens the signal")
    }
}

// MARK: - Sentiment

private struct SentimentCard: View {
    let sentiment: StockSentiment

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionLabel("Sentiment")
                Spacer(minLength: 8)
                Text(sentiment.label)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.color(for: sentiment.direction))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(sentiment.score)")
                    .font(Theme.number(.title2, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(sentiment.score)))
                    .animation(.snappy, value: sentiment.score)
            }

            SentimentBar(score: sentiment.score)

            HStack(spacing: 0) {
                stat("\(sentiment.signals24h)", "Signals 24h", Theme.textPrimary)
                stat("\(sentiment.bullish7d)", "Bullish 7d", Theme.bullish)
                stat("\(sentiment.bearish7d)", "Bearish 7d", Theme.bearish)
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.number(.headline))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Position

private struct PositionCard: View {
    let stock: Stock
    let holding: Holding
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("Your position")
                Spacer()
                Button(action: edit) {
                    Text(holding.isEmpty ? "Add" : "Edit")
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Theme.gold.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }

            if holding.isEmpty {
                Text("Add your shares and average cost to track value and gain.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let code = stock.currencyCode
                let gain = holding.gain(at: stock.price)
                // Three columns when they fit; stacked rows at large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        cell(PriceFormat.shares(holding.shares ?? 0), "Shares")
                        Spacer(minLength: 0)
                        cell(PriceFormat.money(holding.avgCost, currency: code), "Avg cost")
                        Spacer(minLength: 0)
                        cell(PriceFormat.money(holding.marketValue(at: stock.price), currency: code), "Value")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        row("Shares", PriceFormat.shares(holding.shares ?? 0))
                        row("Avg cost", PriceFormat.money(holding.avgCost, currency: code))
                        row("Value", PriceFormat.money(holding.marketValue(at: stock.price), currency: code))
                    }
                }
                if let gain {
                    Divider().overlay(Theme.stroke)
                    HStack(spacing: 8) {
                        Text("Gain")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 8)
                        Text(PriceFormat.signedMoney(gain, currency: code))
                            .font(Theme.number(.subheadline))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(gain > 0 ? Theme.bullish : gain < 0 ? Theme.bearish : Theme.neutral)
                            .contentTransition(.numericText(value: gain))
                        PriceChangePill(percent: holding.gainPct(at: stock.price))
                    }
                }
            }
        }
        .card()
    }

    private func cell(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.number(.subheadline))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.number(.subheadline))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PositionEditor: View {
    let stock: Stock
    @Environment(SignalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var shares: String
    @State private var avgCost: String
    @State private var isSaving = false
    @State private var error: String?

    init(stock: Stock, holding: Holding) {
        self.stock = stock
        _shares = State(initialValue: holding.shares.map { $0.formatted(.number.precision(.fractionLength(0...4)).grouping(.never)) } ?? "")
        _avgCost = State(initialValue: holding.avgCost.map { $0.formatted(.number.precision(.fractionLength(0...4)).grouping(.never)) } ?? "")
    }

    /// Accepts "1,5" or "1.5"; empty means clear the field.
    private static func parse(_ text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        // Drop grouping spaces of any kind (locales use no-break spaces), accept "," or "." as decimal.
        let normalized = String(trimmed.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) })
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return .some(value)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 14) {
                field("Shares", text: $shares, prompt: "0")
                field("Average cost (\(stock.currencyCode))", text: $avgCost, prompt: "0.00")
                if let error {
                    Text(error)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.bearish)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Theme.margin)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("\(stock.ticker) position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(Theme.gold)
                    } else {
                        Button("Save", action: save)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(Theme.textTertiary))
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        }
    }

    private func save() {
        guard let sharesValue = Self.parse(shares), let costValue = Self.parse(avgCost) else {
            error = "Enter numbers zero or above, or leave a field empty."
            return
        }
        isSaving = true
        error = nil
        Task {
            let message = await store.updateHolding(for: stock, shares: sharesValue, avgCost: costValue)
            isSaving = false
            if let message { error = message } else { dismiss() }
        }
    }
}

/// Short x-axis labels: times within a day, dates beyond it.
enum AxisDate {
    static func label(_ date: Date, span: TimeInterval) -> String {
        span < 36 * 3600
            ? date.formatted(.dateTime.hour().minute())
            : date.formatted(.dateTime.month(.abbreviated).day())
    }
}
