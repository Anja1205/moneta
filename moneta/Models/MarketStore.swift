import Foundation
import Observation

/// The single source of truth: the watchlist with positions, live quotes, intraday prices,
/// signals, sentiment and the Top 30. Prices and signals come through the three service
/// protocols (mock or backend); with the Moneta backend, `LiveAccount` adds the user's
/// watchlist rows, sentiment, the Top 30 and the "moneta-live" Realtime channel.
@Observable
final class MarketStore {
    enum LoadState: Equatable { case loading, loaded, failed(String) }

    /// Σ shares×price, today's Σ shares×change, and gain against Σ shares×avg cost.
    struct Portfolio: Equatable {
        let value: Double
        let today: Double
        /// Nil when no position has an average cost.
        let gain: Double?
        let costBasis: Double
        let currency: String
    }

    // MARK: Services
    @ObservationIgnored private let prices: PriceService
    @ObservationIgnored private let monitor: WebMonitorService
    @ObservationIgnored private let agent: SignalAgent
    @ObservationIgnored private let account: LiveAccount?

    // MARK: State
    private(set) var directory: [Company] = []
    private(set) var watched: [Company] = []
    private(set) var quotes: [String: Quote] = [:]
    private(set) var intraday: [String: [PricePoint]] = [:]
    /// Newest first.
    private(set) var signals: [Signal] = []
    private(set) var settings: [String: WatchSettings] = [:]
    /// What the user owns, by ticker.
    private(set) var positions: [String: Position] = [:]
    /// `stock_sentiment` by ticker.
    private(set) var sentiment: [String: Sentiment] = [:]
    /// Top 30 (`companies` rank 1–30) for the Markets tab.
    private(set) var markets: [MarketCompany] = []
    private(set) var marketsState: LoadState = .loading
    /// True while the Realtime channel is subscribed.
    private(set) var isLive = false
    /// Settings new stocks start with.
    var defaultSettings = WatchSettings.standard
    var hapticsEnabled = true

    private(set) var seenIDs: Set<UUID> = []
    /// "TICKER|source" keys the user muted.
    private(set) var mutedKeys: Set<String> = []
    /// Signals that just arrived (highlighted for a few seconds).
    private(set) var freshIDs: Set<UUID> = []
    /// Bumped on each new alert, for haptics.
    private(set) var alertCount = 0
    private(set) var isLoaded = false
    /// Last problem talking to a service, for a banner.
    var errorMessage: String?
    /// Called for each new signal at or above its stock's alert level (Live Activity, notification).
    @ObservationIgnored var onAlert: ((Signal) -> Void)?

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var sentimentTask: Task<Void, Never>?
    /// "TICKER|range" → points, for ranges longer than a day.
    @ObservationIgnored private var historyCache: [String: [PricePoint]] = [:]
    /// Signed-in user; keys the saved watchlist so users don't share one.
    @ObservationIgnored private let userID: UUID?

    init(prices: PriceService, monitor: WebMonitorService, agent: SignalAgent, userID: UUID? = nil,
         account: LiveAccount? = nil) {
        self.prices = prices
        self.monitor = monitor
        self.agent = agent
        self.userID = userID
        self.account = account
    }

    static func mock() -> MarketStore {
        MarketStore(prices: MockPriceService(), monitor: MockWebMonitorService(), agent: MockSignalAgent())
    }

    // MARK: Lifecycle

    /// Loads the saved watchlist (or the account's watchlist on the backend, or the service's
    /// default) and starts live prices and web changes.
    func start() async {
        guard !isLoaded else { return }
        async let marketsDone: Void = loadMarkets()
        directory = (try? await prices.searchCompanies("")) ?? []
        let saved = loadSavedWatchlist()
        var initial = saved ?? []
        if let account {
            // The backend watchlist is the source of truth, positions included.
            do {
                let holdings = try await account.holdings()
                initial = holdings.map(\.company)
                positions = Dictionary(holdings.map { ($0.company.ticker, $0.position) }, uniquingKeysWith: { a, _ in a })
            } catch {
                errorMessage = "Couldn’t load your watchlist. \(error.localizedDescription)"
            }
        } else if saved == nil {
            // The account's own picks, even if none were added; defaults are for services without accounts.
            if let account = await prices.accountWatchlist() {
                initial = account
            } else {
                initial = await prices.defaultWatchlist()
            }
        }
        for company in initial {
            watched.append(company)
            settings[company.ticker] = defaultSettings
            try? await monitor.startWatching(company.ticker, sources: defaultSettings.sources)
        }
        saveWatchlist()
        async let pricesDone: Void = refreshPrices()
        async let signalsDone: Void = loadRecentSignals(for: watched.map(\.ticker))
        async let sentimentDone: Void = refreshSentiment()
        _ = await (pricesDone, signalsDone, sentimentDone)
        await marketsDone
        // Today's seeded signals start as already seen except the latest per stock.
        let latestPerStock = Set(Dictionary(grouping: signals, by: \.ticker).compactMap { $0.value.first?.id })
        seenIDs = Set(signals.map(\.id)).subtracting(latestPerStock)
        isLoaded = true
        listen()
        await startRealtime()
    }

    /// Stops live prices and web changes. Called when the app switches data source or signs out.
    func stop() {
        tickTask?.cancel()
        changeTask?.cancel()
        updateTask?.cancel()
        tickTask = nil
        changeTask = nil
        updateTask = nil
        sentimentTask?.cancel()
        if let account {
            Task { await account.stopRealtime() }
        }
        isLive = false
    }

    /// Sign-out: unsubscribe and clear everything.
    func reset() {
        stop()
        watched = []
        quotes = [:]
        intraday = [:]
        signals = []
        settings = [:]
        positions = [:]
        sentiment = [:]
        markets = []
        historyCache = [:]
        freshIDs = []
        seenIDs = []
        isLoaded = false
    }

    // MARK: Realtime (Moneta backend)

    private func startRealtime() async {
        guard let account else { return }
        await account.startRealtime(LiveAccount.Handlers(
            signalInserted: { [weak self] change in Task { await self?.receive(change) } },
            signalUpdated: { [weak self] change in Task { await self?.receiveUpdate(change) } },
            stockUpdated: { [weak self] row in self?.apply(row) },
            watchlistChanged: { [weak self] in Task { await self?.reloadHoldings() } },
            priceInserted: { [weak self] row in self?.apply(row) },
            companyUpdated: { [weak self] row in self?.apply(row) },
            liveChanged: { [weak self] live in self?.isLive = live }
        ))
    }

    /// Back in the foreground: resubscribe if the channel dropped.
    func reconnect() async {
        guard let account, isLoaded, !isLive else { return }
        await account.stopRealtime()
        await startRealtime()
    }

    private func ticker(for stockID: UUID) -> String? {
        watched.first { $0.stockID == stockID }?.ticker
    }

    /// `stocks` UPDATE: new price for a watched stock.
    private func apply(_ row: StockRow) {
        guard isWatching(row.ticker), let quote = row.quote else { return }
        apply(PriceTick(ticker: row.ticker, point: PricePoint(date: quote.updatedAt, price: quote.price)))
        quotes[row.ticker] = quote
    }

    /// `price_history` INSERT for a watched stock.
    private func apply(_ row: PriceHistoryRow) {
        guard let ticker = ticker(for: row.stockID), let point = row.point else { return }
        apply(PriceTick(ticker: ticker, point: point))
        historyCache = historyCache.filter { !$0.key.hasPrefix("\(ticker)|") }
    }

    /// `companies` UPDATE: refresh the Markets row.
    private func apply(_ row: MarketCompany) {
        guard let index = markets.firstIndex(where: { $0.ticker == row.ticker }) else { return }
        markets[index] = row
    }

    /// `watchlist` changed (here or on another device): add, remove and update positions.
    private func reloadHoldings() async {
        guard let account, let holdings = try? await account.holdings() else { return }
        let tickers = Set(holdings.map(\.company.ticker))
        for holding in holdings {
            let ticker = holding.company.ticker
            positions[ticker] = holding.position
            if let index = watched.firstIndex(where: { $0.ticker == ticker }) {
                if watched[index].stockID == nil { watched[index].stockID = holding.company.stockID }
            } else {
                await watchLocally(holding.company)
            }
        }
        for company in watched where !tickers.contains(company.ticker) {
            removeLocally(company.ticker)
        }
        saveWatchlist()
        listen()
        scheduleSentimentRefresh()
    }

    // MARK: Sentiment and Top 30

    func refreshSentiment() async {
        guard let account else { return }
        let ids = watched.compactMap(\.stockID)
        guard let rows = try? await account.sentiment(ids) else { return }
        var byTicker: [String: Sentiment] = [:]
        for row in rows {
            if let ticker = ticker(for: row.stockID) { byTicker[ticker] = row }
        }
        sentiment = byTicker
    }

    /// Re-fetch sentiment 2 s after the last signal change.
    private func scheduleSentimentRefresh() {
        guard account != nil else { return }
        sentimentTask?.cancel()
        sentimentTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.refreshSentiment()
        }
    }

    func loadMarkets() async {
        guard let account else {
            marketsState = .failed("The Top 30 needs the Moneta backend. Switch the data source in Settings.")
            return
        }
        if markets.isEmpty { marketsState = .loading }
        do {
            markets = try await account.topCompanies()
            marketsState = .loaded
        } catch {
            marketsState = .failed("Couldn’t load the Top 30. Pull to try again.")
        }
    }

    // MARK: Positions

    var holdings: [Holding] {
        watched.map { Holding(company: $0, position: positions[$0.ticker] ?? Position()) }
    }

    /// Nil until at least one position has shares and a price.
    var portfolio: Portfolio? {
        var value = 0.0, today = 0.0, cost = 0.0, costCovered = 0.0
        var currency = "USD"
        var any = false
        for company in watched {
            guard let shares = positions[company.ticker]?.shares, shares > 0,
                  let quote = quotes[company.ticker] else { continue }
            any = true
            currency = quote.currency
            value += shares * quote.price
            today += shares * quote.change
            if let avg = positions[company.ticker]?.avgCost {
                cost += shares * avg
                costCovered += shares * quote.price
            }
        }
        guard any else { return nil }
        return Portfolio(value: value, today: today, gain: cost > 0 ? costCovered - cost : nil,
                         costBasis: cost, currency: currency)
    }

    func updatePosition(_ ticker: String, shares: Double?, avgCost: Double?) async {
        let position = Position(shares: shares, avgCost: avgCost)
        let previous = positions[ticker]
        positions[ticker] = position
        guard let account, let stockID = company(ticker)?.stockID ?? watched.first(where: { $0.ticker == ticker })?.stockID else { return }
        do {
            try await account.updatePosition(stockID: stockID, position)
        } catch {
            positions[ticker] = previous
            errorMessage = "Couldn’t save your \(ticker) position. \(error.localizedDescription)"
        }
    }

    func removePosition(_ ticker: String) async {
        await updatePosition(ticker, shares: nil, avgCost: nil)
    }

    func removeFromWatchlist(_ ticker: String) async {
        await removeStock(ticker)
    }

    private func refreshPrices() async {
        await withTaskGroup(of: Void.self) { group in
            for company in watched {
                group.addTask { await self.loadPrice(company, trackIfMissing: true) }
            }
        }
    }

    /// Quote and today's prices for one company. Asks the backend to track it if it has no price.
    private func loadPrice(_ company: Company, trackIfMissing: Bool) async {
        var quote = try? await prices.quote(for: company.ticker)
        if quote == nil, trackIfMissing {
            try? await prices.track(company)
            quote = try? await prices.quote(for: company.ticker)
        }
        quotes[company.ticker] = quote
        var series = (try? await prices.history(for: company.ticker, range: .day)) ?? []
        // Add the live quote only if it's news; an unchanged price after the close would
        // stretch a flat line across the closed market.
        if let quote, let last = series.last {
            if last.date < quote.updatedAt, abs(last.price - quote.price) > 0.0001 {
                series.append(PricePoint(date: quote.updatedAt, price: quote.price))
            }
        } else if let quote {
            series.append(PricePoint(date: quote.updatedAt, price: quote.price))
        }
        intraday[company.ticker] = series
    }

    // MARK: Persistence

    @ObservationIgnored private lazy var watchlistKey =
        ["watchlist", "\(type(of: prices))", userID?.uuidString].compactMap { $0 }.joined(separator: ".")

    private func loadSavedWatchlist() -> [Company]? {
        guard let data = UserDefaults.standard.data(forKey: watchlistKey) else { return nil }
        return try? JSONDecoder().decode([Company].self, from: data)
    }

    private func saveWatchlist() {
        if let data = try? JSONEncoder().encode(watched) {
            UserDefaults.standard.set(data, forKey: watchlistKey)
        }
    }

    private func loadRecentSignals(for tickers: [String]) async {
        guard let changes = try? await monitor.recentChanges(for: tickers) else { return }
        for change in changes {
            if let signal = await assess(change) {
                insert(signal)
            }
        }
    }

    private func listen() {
        tickTask?.cancel()
        let tickers = watched.map(\.ticker)
        tickTask = Task { [weak self, prices] in
            for await tick in prices.ticks(for: tickers) {
                self?.apply(tick)
            }
        }
        if changeTask == nil {
            changeTask = Task { [weak self, monitor] in
                for await change in monitor.changes() {
                    await self?.receive(change)
                }
            }
        }
        if updateTask == nil {
            updateTask = Task { [weak self, monitor] in
                for await change in monitor.updates() {
                    await self?.receiveUpdate(change)
                }
            }
        }
    }

    private func apply(_ tick: PriceTick) {
        if let last = intraday[tick.ticker]?.last, last.date >= tick.point.date {
            // Same timestamp again: just update the price.
            if last.date == tick.point.date, var series = intraday[tick.ticker], !series.isEmpty {
                series[series.count - 1] = tick.point
                intraday[tick.ticker] = series
            }
        } else if let last = intraday[tick.ticker]?.last, abs(last.price - tick.point.price) < 0.0001 {
            // Same price again (e.g. the market is closed): don't extend the line.
        } else {
            intraday[tick.ticker, default: []].append(tick.point)
        }
        if let quote = quotes[tick.ticker] {
            quotes[tick.ticker] = Quote(price: tick.point.price, previousClose: quote.previousClose,
                                        updatedAt: tick.point.date, currency: quote.currency)
        }
    }

    private func receive(_ change: WebChange) async {
        guard isWatching(change.ticker), !signals.contains(where: { $0.id == change.id }),
              let signal = await assess(change) else { return }
        insert(signal)
        highlight(signal.id)
        // Notifications and the Live Activity: only newly found, important (4+) signals.
        if signal.isNew, signal.impact >= .high, isAlert(signal) {
            alertCount += 1
            onAlert?(signal)
        }
        scheduleSentimentRefresh()
    }

    /// A row the backend re-scored: replace our copy in place and flash it. Never alerts.
    private func receiveUpdate(_ change: WebChange) async {
        guard isWatching(change.ticker), signals.contains(where: { $0.id == change.id }),
              let updated = await assess(change),
              let index = signals.firstIndex(where: { $0.id == change.id }),
              signals[index] != updated else { return }
        signals[index] = updated
        highlight(updated.id)
        scheduleSentimentRefresh()
    }

    private func highlight(_ id: UUID) {
        freshIDs.insert(id)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.freshIDs.remove(id)
        }
    }

    /// Pull to refresh: re-reads quotes and the recent signals, replacing re-scored ones in place.
    /// `fetchNews` also asks the backend to fetch news now (`poll-news`), for the feed.
    func refresh(fetchNews: Bool = false) async {
        if let account, fetchNews {
            try? await account.pollNews()
        }
        historyCache = [:]
        if account != nil {
            await reloadHoldings()
            await loadMarkets()
        }
        let tickers = watched.map(\.ticker)
        guard !tickers.isEmpty else { return }
        if let changes = try? await monitor.recentChanges(for: tickers) {
            for change in changes {
                guard let signal = await assess(change) else { continue }
                if let index = signals.firstIndex(where: { $0.id == signal.id }) {
                    if signals[index] != signal {
                        signals[index] = signal
                        highlight(signal.id)
                    }
                } else {
                    insert(signal)
                }
            }
        }
        await refreshPrices()
        await refreshSentiment()
    }

    private func assess(_ change: WebChange) async -> Signal? {
        guard let company = company(change.ticker),
              settings[change.ticker]?.sources.contains(change.source) ?? true,
              let verdict = try? await agent.assess(change, company: company) else { return nil }
        return Signal(
            id: change.id, ticker: change.ticker, source: change.source, impact: verdict.impact,
            time: change.detectedAt, title: change.title, why: verdict.why, url: change.url,
            facts: change.facts, diff: change.diff, direction: verdict.direction, isNew: change.isNew
        )
    }

    private func insert(_ signal: Signal) {
        guard !signals.contains(where: { $0.id == signal.id }) else { return }
        signals.append(signal)
        signals.sort { $0.time > $1.time }
    }

    // MARK: Watchlist

    func isWatching(_ ticker: String) -> Bool { watched.contains { $0.ticker == ticker } }

    func company(_ ticker: String) -> Company? {
        directory.first { $0.ticker == ticker } ?? watched.first { $0.ticker == ticker }
    }

    func search(_ query: String) async -> [Company] {
        (try? await prices.searchCompanies(query)) ?? []
    }

    /// Like `search` but passes errors on, for screens that show an error state.
    func searchCompanies(_ query: String) async throws -> [Company] {
        try await prices.searchCompanies(query)
    }

    func addStock(_ company: Company, settings watch: WatchSettings) async {
        guard !isWatching(company.ticker) else { return }
        settings[company.ticker] = watch
        do {
            try await prices.track(company)
        } catch {
            errorMessage = "Couldn’t start tracking \(company.ticker). \(error.localizedDescription)"
        }
        await watchLocally(company)
        saveWatchlist()
        listen()
        // add-stock created the watchlist row; pick up its stock id (sentiment, positions).
        await reloadHoldings()
    }

    /// Adds a company to the local state only (the backend row already exists or isn't needed).
    private func watchLocally(_ company: Company) async {
        guard !isWatching(company.ticker) else { return }
        if settings[company.ticker] == nil { settings[company.ticker] = defaultSettings }
        try? await monitor.startWatching(company.ticker, sources: settings[company.ticker]?.sources ?? defaultSettings.sources)
        watched.append(company)
        if !directory.contains(where: { $0.ticker == company.ticker }) { directory.append(company) }
        await loadPrice(company, trackIfMissing: false)
        await loadRecentSignals(for: [company.ticker])
    }

    private func removeLocally(_ ticker: String) {
        watched.removeAll { $0.ticker == ticker }
        signals.removeAll { $0.ticker == ticker }
        settings[ticker] = nil
        quotes[ticker] = nil
        intraday[ticker] = nil
        positions[ticker] = nil
        sentiment[ticker] = nil
        historyCache = historyCache.filter { !$0.key.hasPrefix("\(ticker)|") }
    }

    /// Stops watching: removes it here and deletes the user's watchlist row on the backend.
    func removeStock(_ ticker: String) async {
        let stockID = watched.first { $0.ticker == ticker }?.stockID
        removeLocally(ticker)
        saveWatchlist()
        try? await monitor.stopWatching(ticker)
        listen()
        if let account, let stockID {
            do {
                try await account.removeFromWatchlist(stockID: stockID)
            } catch {
                errorMessage = "Couldn’t remove \(ticker) from your watchlist. \(error.localizedDescription)"
            }
        }
    }

    /// Price points for a range, cached per stock and range (1D is the live intraday series).
    func history(_ ticker: String, range: ChartRange) async -> [PricePoint] {
        if range == .day { return intraday[ticker] ?? [] }
        let key = "\(ticker)|\(range.rawValue)"
        if let cached = historyCache[key] { return cached }
        let points = (try? await prices.history(for: ticker, range: range)) ?? []
        if !points.isEmpty { historyCache[key] = points }
        return points
    }

    // MARK: Signals

    func signals(for ticker: String) -> [Signal] { signals.filter { $0.ticker == ticker } }

    /// What a stock's tile shows: its newest signal with impact 3+, else its newest of any impact.
    func latestImportant(for ticker: String) -> Signal? {
        let mine = signals(for: ticker)
        return mine.first { $0.impact.isImportant } ?? mine.first
    }

    /// 1 for the day's first signal on a stock, 2 for the next…
    func pinNumber(for signal: Signal) -> Int {
        signals(for: signal.ticker).sorted { $0.time < $1.time }.firstIndex { $0.id == signal.id }.map { $0 + 1 } ?? 1
    }

    func isMuted(_ signal: Signal) -> Bool { mutedKeys.contains(muteKey(signal)) }

    func toggleMute(_ signal: Signal) {
        let key = muteKey(signal)
        if mutedKeys.contains(key) { mutedKeys.remove(key) } else { mutedKeys.insert(key) }
    }

    func unmute(_ key: String) { mutedKeys.remove(key) }

    private func muteKey(_ signal: Signal) -> String { "\(signal.ticker)|\(signal.source.rawValue)" }

    /// At or above the stock's alert level and not muted.
    func isAlert(_ signal: Signal) -> Bool {
        let level = settings[signal.ticker]?.alertLevel ?? defaultSettings.alertLevel
        return signal.impact >= level.minimum && !isMuted(signal)
    }

    func newCount(for ticker: String) -> Int {
        signals(for: ticker).filter { !seenIDs.contains($0.id) && isAlert($0) }.count
    }

    func markSeen(_ ticker: String) {
        seenIDs.formUnion(signals(for: ticker).map(\.id))
    }

    func markSeen(_ signal: Signal) { seenIDs.insert(signal.id) }

    /// The newest high-impact, unmuted signal.
    var latestWarning: Signal? {
        signals.first { $0.impact >= .high && !isMuted($0) } ?? signals.first { isAlert($0) }
    }

    /// How the price moved after the signal: the largest move within two hours, and when it
    /// reached 85% of it. Works on any intraday series, mock or real.
    func reaction(to signal: Signal) -> MarketReaction? {
        guard let series = intraday[signal.ticker],
              let start = series.firstIndex(where: { $0.date >= signal.time }) else { return nil }
        let base = series[start].price
        let window = series[start...].prefix { $0.date <= signal.time.addingTimeInterval(2 * 3600) }
        let hourPassed = (series.last?.date ?? signal.time) >= signal.time.addingTimeInterval(3600)
        guard window.count > 1, base > 0 else {
            return MarketReaction(signalTime: signal.time, move: 0, at: nil, settled: hourPassed)
        }
        let moves = window.map { ($0.date, $0.price / base - 1) }
        guard let extreme = moves.max(by: { abs($0.1) < abs($1.1) }) else { return nil }
        guard abs(extreme.1) >= 0.003 else {
            return MarketReaction(signalTime: signal.time, move: moves.last?.1 ?? 0, at: nil, settled: hourPassed)
        }
        let reached = moves.first { abs($0.1) >= abs(extreme.1) * 0.85 && $0.1.sign == extreme.1.sign }
        return MarketReaction(signalTime: signal.time, move: extreme.1, at: reached?.0)
    }

    // MARK: Settings

    func updateSettings(_ ticker: String, _ watch: WatchSettings) async {
        settings[ticker] = watch
        try? await monitor.startWatching(ticker, sources: watch.sources)
    }

    // MARK: Preview

    /// A store already loaded with mock data, for #Preview.
    static func preview() -> MarketStore {
        let store = MarketStore.mock()
        Task { await store.start() }
        return store
    }
}
