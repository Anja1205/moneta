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
                    if !store.stocks.isEmpty {
                        PortfolioHeader()
                            .watchlistRow(top: 4, bottom: 10)
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

/// Top of the watchlist: total position value (when the user entered shares) or a count of watched
/// stocks, with the day's average move and a faint gold glow.
private struct PortfolioHeader: View {
    @Environment(SignalStore.self) private var store

    /// Day change of the portfolio in the main currency, from each position's `price_change`.
    private var dayChange: (amount: Double, percent: Double)? {
        guard let currency = mainCurrency else { return nil }
        var change = 0.0, previous = 0.0
        for stock in store.stocks where stock.currencyCode == currency {
            guard let shares = store.holding(for: stock).shares, shares != 0,
                  let price = stock.price, let delta = stock.priceChange else { continue }
            change += shares * delta
            previous += shares * (price - delta)
        }
        guard previous > 0 else { return nil }
        return (change, change / previous * 100)
    }

    /// The currency with the largest total, so mixed portfolios still show one headline number.
    private var mainCurrency: String? {
        store.portfolioValue.max { $0.value < $1.value }?.key
    }

    /// Average of today's percent moves across watched stocks that have one.
    private var averageMove: Double? {
        let moves = store.stocks.compactMap(\.priceChangePct)
        guard !moves.isEmpty else { return nil }
        return moves.reduce(0, +) / Double(moves.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let currency = mainCurrency, let total = store.portfolioValue[currency] {
                SectionLabel("Your positions")
                Text(PriceFormat.money(total, currency: currency))
                    .font(Theme.number(.largeTitle, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: total))
                    .animation(.snappy, value: total)
                if let dayChange {
                    HStack(spacing: 8) {
                        Text(PriceFormat.signedMoney(dayChange.amount, currency: currency))
                            .font(Theme.number(.subheadline))
                            .monospacedDigit()
                            .foregroundStyle(dayChange.amount >= 0 ? Theme.bullish : Theme.bearish)
                            .contentTransition(.numericText(value: dayChange.amount))
                        PriceChangePill(percent: dayChange.percent)
                        Text("today")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            } else {
                SectionLabel("Watching")
                Text("\(store.stocks.count) \(store.stocks.count == 1 ? "stock" : "stocks")")
                    .font(Theme.number(.largeTitle, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(store.stocks.count)))
                    .animation(.snappy, value: store.stocks.count)
                if let averageMove {
                    HStack(spacing: 8) {
                        PriceChangePill(percent: averageMove)
                        Text("average move today")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .background(alignment: .topLeading) {
            GoldGlow(width: 260, height: 120, intensity: 0.7)
                .offset(x: -50, y: -20)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - StockCard

struct StockCard: View {
    let stock: Stock
    let latest: Signal?
    var sentiment: StockSentiment? = nil
    /// Set briefly when a live update moves the price.
    var flash: Direction? = nil
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

            HStack(spacing: 8) {
                if let sentiment {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                        Text("\(sentiment.score)")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(sentiment.score)))
                        Text(sentiment.label)
                            .lineLimit(1)
                    }
                    .font(Theme.caption.weight(.medium))
                    .foregroundStyle(Theme.color(for: sentiment.direction))
                    .animation(.snappy, value: sentiment.score)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Sentiment \(sentiment.score), \(sentiment.label)")
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
