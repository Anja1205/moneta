import SwiftUI

struct WatchlistView: View {
    @Environment(SignalStore.self) private var store
    @State private var path = NavigationPath()
    @State private var showingAddStock = false
    @State private var pendingRemoval: Stock?

    var body: some View {
        @Bindable var store = store

        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                List {
                    if let message = store.errorMessage {
                        ErrorBanner(message: message) { store.errorMessage = nil }
                            .watchlistRow()
                    }
                    if !store.portfolioValue.isEmpty {
                        PortfolioHeader()
                            .watchlistRow(top: 4, bottom: Theme.cardSpacing / 2)
                    }
                    if store.stocks.isEmpty {
                        WatchlistEmptyState(isLoading: store.isLoading) { showingAddStock = true }
                            .watchlistRow()
                    } else {
                        ForEach(store.stocks) { stock in
                            let latest = store.latestSignal(for: stock)
                            Button {
                                path.append(stock)
                            } label: {
                                StockCard(
                                    stock: stock,
                                    latest: latest,
                                    sentiment: store.sentiment[stock.id],
                                    flash: store.priceFlash[stock.id],
                                    holding: store.holding(for: stock),
                                    isFresh: latest.map { store.freshIds.contains($0.id) } ?? false,
                                    now: context.date
                                )
                            }
                            .buttonStyle(PressableCardStyle())
                            .watchlistRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    pendingRemoval = stock
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .tint(Theme.bearish)
                            }
                            .contextMenu {
                                if let latest {
                                    Button("Open latest signal", systemImage: "doc.text") {
                                        path.append(latest)
                                    }
                                }
                                Button("Remove from watchlist", systemImage: "trash", role: .destructive) {
                                    pendingRemoval = stock
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .demoScrollAnchor()
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 24, for: .scrollContent)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: store.stocks.map(\.id))
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .refreshable {
                await store.refreshAll()
                await store.load()
            }
            .toolbar {
                if #available(iOS 26, *) {
                    ToolbarItem(placement: .topBarLeading) { wordmark }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { wordmark }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    LivePill(isLive: store.isLive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddStock = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Add stock")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Stock.self) { stock in
                StockDetailView(stock: stock)
            }
            .navigationDestination(for: Signal.self) { signal in
                SignalDetailView(signal: signal, stock: store.stock(for: signal))
                    .toolbarBackground(Theme.background, for: .navigationBar)
            }
        }
        .confirmationDialog(
            pendingRemoval.map { "Stop watching \($0.ticker)?" } ?? "",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { stock in
            Button("Remove \(stock.ticker)", role: .destructive) {
                Task { await store.removeStock(stock) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { stock in
            Text("\(stock.name) and its signals will leave your watchlist. You can add it back any time.")
        }
        #if DEBUG
        .task(id: store.stocks.count) {
            guard DemoMode.isMain, path.isEmpty, !store.stocks.isEmpty else { return }
            switch DemoMode.screen {
            case "stock", "position", "callout": path.append(store.stocks[0])
            case "stock2": path.append(store.stocks[2])
            case "nopos": path.append(store.stocks[3])
            case "signal":
                if let signal = store.signals.first(where: { $0.stockID == store.stocks[1].id }) { path.append(signal) }
            case "search": showingAddStock = true
            default: break
            }
        }
        #endif
        .sheet(isPresented: $showingAddStock) {
            StockSearchView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
    }

    private var wordmark: some View {
        Wordmark(size: 26)
    }
}

// MARK: - Portfolio header

/// Top of the watchlist when the user owns anything: total value, today's change, total gain/loss,
/// and an allocation bar in each holding's brand colour. Mixed currencies use the largest one.
private struct PortfolioHeader: View {
    @Environment(SignalStore.self) private var store

    private struct Slice: Identifiable {
        let stock: Stock
        let value: Double
        var id: UUID { stock.id }
        var color: Color { stock.brandColor.map(Color.init(hex:)) ?? Theme.gold }
    }

    /// The currency with the largest total.
    private var currency: String? {
        store.portfolioValue.max { $0.value < $1.value }?.key
    }

    private var slices: [Slice] {
        guard let currency else { return [] }
        return store.stocks
            .filter { $0.currencyCode == currency }
            .compactMap { stock in
                store.holding(for: stock).marketValue(at: stock.price).map { Slice(stock: stock, value: $0) }
            }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
    }

    private var total: Double { slices.reduce(0) { $0 + $1.value } }

    /// Sum of shares × price_change, as money and as % of yesterday's value.
    private var today: (amount: Double, percent: Double)? {
        var change = 0.0, previous = 0.0, any = false
        for slice in slices {
            guard let delta = slice.stock.priceChange, let shares = store.holding(for: slice.stock).shares else { continue }
            any = true
            change += shares * delta
            previous += slice.value - shares * delta
        }
        guard any, previous > 0 else { return nil }
        return (change, change / previous * 100)
    }

    /// Market value minus cost basis, over holdings that have an average cost.
    private var gain: (amount: Double, percent: Double)? {
        var value = 0.0, cost = 0.0
        for slice in slices {
            guard let basis = store.holding(for: slice.stock).costBasis else { continue }
            value += slice.value
            cost += basis
        }
        guard cost > 0 else { return nil }
        return (value - cost, (value - cost) / cost * 100)
    }

    private var otherCurrencies: Int { max(store.portfolioValue.count - 1, 0) }

    var body: some View {
        if let currency, !slices.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Your portfolio")
                    Text(PriceFormat.money(total, currency: currency))
                        .font(Theme.number(.largeTitle, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: total))
                        .animation(.snappy, value: total)
                }
                .background(alignment: .leading) {
                    GoldGlow(width: 260, height: 110, intensity: 0.6)
                        .offset(x: -50)
                }

                VStack(spacing: 8) {
                    if let today {
                        changeRow("Today", amount: today.amount, percent: today.percent, currency: currency)
                    }
                    if let gain {
                        changeRow("Total gain/loss", amount: gain.amount, percent: gain.percent, currency: currency)
                    }
                }

                allocation

                if otherCurrencies > 0 {
                    Text("Plus holdings in \(otherCurrencies) other \(otherCurrencies == 1 ? "currency" : "currencies"), not included.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    private func changeRow(_ label: String, amount: Double, percent: Double, currency: String) -> some View {
        let color = amount > 0 ? Theme.bullish : amount < 0 ? Theme.bearish : Theme.neutral
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                rowLabel(label)
                Spacer(minLength: 8)
                rowValue(amount, percent: percent, currency: currency, color: color)
            }
            VStack(alignment: .leading, spacing: 4) {
                rowLabel(label)
                HStack(spacing: 8) { rowValue(amount, percent: percent, currency: currency, color: color) }
            }
            // ViewThatFits centres a narrower child; pin the wrapped layout to the leading edge.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.body)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private func rowValue(_ amount: Double, percent: Double, currency: String, color: Color) -> some View {
        Text(PriceFormat.signedMoney(amount, currency: currency))
            .font(Theme.number(.subheadline))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .contentTransition(.numericText(value: amount))
            .animation(.snappy, value: amount)
        PriceChangePill(percent: percent)
    }

    private var allocation: some View {
        let slices = slices
        let total = total
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let gaps = CGFloat(max(slices.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(slices) { slice in
                        Rectangle()
                            .fill(slice.color)
                            .frame(width: max((proxy.size.width - gaps) * slice.value / total, 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: slices.map(\.value))

            // Legend: biggest holdings first, wrapping to more lines when needed.
            LegendFlow(spacing: 12, lineSpacing: 6) {
                ForEach(slices.prefix(6)) { slice in
                    HStack(spacing: 5) {
                        Circle().fill(slice.color).frame(width: 7, height: 7)
                        Text(slice.stock.ticker)
                            .foregroundStyle(Theme.textSecondary)
                        Text((slice.value / total).formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .font(Theme.caption)
                    .fixedSize()
                }
                if slices.count > 6 {
                    Text("+\(slices.count - 6) more")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Allocation: " + slices.map {
            "\($0.stock.ticker) \(($0.value / total).formatted(.percent.precision(.fractionLength(0))))"
        }.joined(separator: ", "))
    }
}

/// Lays children out left to right and wraps to a new line when the row is full.
private struct LegendFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

// MARK: - StockCard

struct StockCard: View {
    let stock: Stock
    let latest: Signal?
    var sentiment: StockSentiment? = nil
    /// Set briefly when a live update moves the price.
    var flash: Direction? = nil
    /// The user's position; shows "10 shares · $1,234" under the name when they own some.
    var holding: Holding = Holding()
    let isFresh: Bool
    let now: Date

    private var brand: Color { stock.brandColor.map(Color.init(hex:)) ?? Theme.gold }
    private var directionColor: Color { latest.map { Theme.color(for: $0.direction) } ?? Theme.neutral }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Always true: a stock without a price shows "—" so cards line up.
    private var hasQuote: Bool { true }

    private var stackedQuote: Bool {
        typeSize >= .xLarge || PriceFormat.money(stock.price, currency: stock.currencyCode).count > 11
    }

    @ViewBuilder
    private var quote: some View {
        priceText
            .minimumScaleFactor(0.6)
        if stock.priceChangePct != nil || stock.priceChange != nil {
            PriceChangePill(percent: stock.priceChangePct, change: stock.priceChange, currency: stock.currencyCode)
        }
    }

    private func positionLine(_ shares: Double) -> some View {
        let value = holding.marketValue(at: stock.price)
        let text = value.map { "\(PriceFormat.shareCount(shares)) · \(PriceFormat.money($0, currency: stock.currencyCode))" }
            ?? PriceFormat.shareCount(shares)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .monospacedDigit()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText(value: value ?? 0))
                .animation(.snappy, value: value)
        }
        .font(Theme.caption.weight(.semibold))
        .foregroundStyle(Theme.gold)
        .accessibilityLabel("You own \(text)")
    }

    private var priceText: some View {
        Text(PriceFormat.money(stock.price, currency: stock.currencyCode))
            .font(Theme.number(.title3, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(stock.price == nil ? Theme.textTertiary : Theme.textPrimary)
            .lineLimit(1)
            .contentTransition(.numericText(value: stock.price ?? 0))
            .animation(.snappy, value: stock.price)
            .priceFlash(flash)
            .accessibilityLabel(stock.price == nil ? "No price yet" : PriceFormat.money(stock.price, currency: stock.currencyCode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CompanyLogo(stock: stock, size: .card)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(stock.ticker)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if stock.isDemo { DemoTag() }
                    }
                    Text(stock.name)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let shares = holding.shares, shares > 0 {
                        positionLine(shares)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasQuote && !stackedQuote {
                    VStack(alignment: .trailing, spacing: 4) { quote }
                        .fixedSize()
                }
            }

            if hasQuote && stackedQuote {
                // Large text or long prices: the quote gets its own row so the name keeps its width.
                HStack(spacing: 8) { quote }
            }

            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(directionColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                    .accessibilityLabel(latest?.direction.label ?? "No signal")
                Text(latest?.why ?? "No signals yet. Moneta is watching the web for \(stock.name).")
                    .font(Theme.body)
                    .foregroundStyle(latest == nil ? Theme.textTertiary : Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let sentiment {
                SentimentMiniBar(sentiment: sentiment)
            }

            HStack(spacing: 8) {
                if let sentiment {
                    Text("Web: \(sentiment.label)")
                        .font(Theme.caption.weight(.medium))
                        .foregroundStyle(SentimentScale.color(for: sentiment))
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 4)
                if let latest {
                    Text(RelativeTime.string(for: latest.detectedDate, now: now))
                        .font(Theme.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(isFresh ? Theme.gold : Theme.textTertiary)
                }
            }
            .padding(.top, -4)
        }
        .padding(.leading, 6)
        .card(highlighted: isFresh)
        .overlay(alignment: .leading) {
            // Brand accent inside the card, clear of the rounded corners and border.
            Capsule()
                .fill(brand)
                .frame(width: 3)
                .padding(.vertical, 18)
                .padding(.leading, 8)
                .accessibilityHidden(true)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty state

private struct WatchlistEmptyState: View {
    let isLoading: Bool
    let addStock: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView().tint(Theme.gold)
                Text("Loading your watchlist…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: "binoculars")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.gold)
                Text("Your watchlist is empty")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Add a stock and Moneta watches its news, investor relations, careers and pricing pages for you.")
                    .font(Theme.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Add stock", systemImage: "plus", action: addStock)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .card()
    }
}

private extension View {
    /// Card-style list row: no separator, clear background, card gutters.
    /// 12pt between cards (6 + 6), 16pt screen margins.
    func watchlistRow(top: CGFloat = Theme.cardSpacing / 2, bottom: CGFloat = Theme.cardSpacing / 2) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: Theme.margin, bottom: bottom, trailing: Theme.margin))
    }
}
