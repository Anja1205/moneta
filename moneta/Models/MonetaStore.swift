import Foundation
import Observation

/// App state: the watchlist, live quotes, intraday prices and signals.
/// Talks only to the three service protocols, so real services can replace the mocks.
@Observable
final class MonetaStore {
    // MARK: Services
    @ObservationIgnored private let prices: PriceService
    @ObservationIgnored private let monitor: WebMonitorService
    @ObservationIgnored private let agent: SignalAgent

    // MARK: State
    private(set) var directory: [Company] = []
    private(set) var watched: [Company] = []
    private(set) var quotes: [String: Quote] = [:]
    private(set) var intraday: [String: [PricePoint]] = [:]
    /// Newest first.
    private(set) var signals: [Signal] = []
    private(set) var settings: [String: WatchSettings] = [:]
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

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?

    init(prices: PriceService, monitor: WebMonitorService, agent: SignalAgent) {
        self.prices = prices
        self.monitor = monitor
        self.agent = agent
    }

    static func mock() -> MonetaStore {
        MonetaStore(prices: MockPriceService(), monitor: MockWebMonitorService(), agent: MockSignalAgent())
    }

    // MARK: Lifecycle

    /// Loads the saved watchlist (or the service's default) and starts live prices and web changes.
    func start() async {
        guard !isLoaded else { return }
        directory = (try? await prices.searchCompanies("")) ?? []
        let saved = loadSavedWatchlist()
        var initial = saved ?? []
        if saved == nil { initial = await prices.defaultWatchlist() }
        for company in initial {
            watched.append(company)
            settings[company.ticker] = defaultSettings
            try? await monitor.startWatching(company.ticker, sources: defaultSettings.sources)
        }
        if saved == nil { saveWatchlist() }
        await refreshPrices()
        await loadRecentSignals(for: watched.map(\.ticker))
        // Today's seeded signals start as already seen except the latest per stock.
        let latestPerStock = Set(Dictionary(grouping: signals, by: \.ticker).compactMap { $0.value.first?.id })
        seenIDs = Set(signals.map(\.id)).subtracting(latestPerStock)
        isLoaded = true
        listen()
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
        if let quote, series.last.map({ $0.date < quote.updatedAt }) ?? true {
            series.append(PricePoint(date: quote.updatedAt, price: quote.price))
        }
        intraday[company.ticker] = series
    }

    // MARK: Persistence

    @ObservationIgnored private lazy var watchlistKey = "watchlist.\(type(of: prices))"

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
    }

    private func apply(_ tick: PriceTick) {
        if let last = intraday[tick.ticker]?.last, last.date >= tick.point.date {
            // Same timestamp again: just update the price.
            if last.date == tick.point.date { intraday[tick.ticker]?[intraday[tick.ticker]!.count - 1] = tick.point }
        } else {
            intraday[tick.ticker, default: []].append(tick.point)
        }
        if let quote = quotes[tick.ticker] {
            quotes[tick.ticker] = Quote(price: tick.point.price, previousClose: quote.previousClose,
                                        updatedAt: tick.point.date, currency: quote.currency)
        }
    }

    private func receive(_ change: WebChange) async {
        guard let signal = await assess(change) else { return }
        insert(signal)
        freshIDs.insert(signal.id)
        if isAlert(signal) { alertCount += 1 }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.freshIDs.remove(signal.id)
        }
    }

    private func assess(_ change: WebChange) async -> Signal? {
        guard let company = company(change.ticker),
              settings[change.ticker]?.sources.contains(change.source) ?? true,
              let verdict = try? await agent.assess(change, company: company) else { return nil }
        return Signal(
            id: change.id, ticker: change.ticker, source: change.source, impact: verdict.impact,
            time: change.detectedAt, title: change.title, why: verdict.why, url: change.url,
            facts: change.facts, diff: change.diff
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

    func addStock(_ company: Company, settings watch: WatchSettings) async {
        guard !isWatching(company.ticker) else { return }
        settings[company.ticker] = watch
        do {
            try await prices.track(company)
        } catch {
            errorMessage = "Couldn’t start tracking \(company.ticker). \(error.localizedDescription)"
        }
        try? await monitor.startWatching(company.ticker, sources: watch.sources)
        watched.append(company)
        if !directory.contains(where: { $0.ticker == company.ticker }) { directory.append(company) }
        saveWatchlist()
        await loadPrice(company, trackIfMissing: false)
        await loadRecentSignals(for: [company.ticker])
        listen()
    }

    func removeStock(_ ticker: String) async {
        watched.removeAll { $0.ticker == ticker }
        signals.removeAll { $0.ticker == ticker }
        settings[ticker] = nil
        quotes[ticker] = nil
        intraday[ticker] = nil
        saveWatchlist()
        try? await monitor.stopWatching(ticker)
        listen()
    }

    func history(_ ticker: String, range: ChartRange) async -> [PricePoint] {
        if range == .day { return intraday[ticker] ?? [] }
        return (try? await prices.history(for: ticker, range: range)) ?? []
    }

    // MARK: Signals

    func signals(for ticker: String) -> [Signal] { signals.filter { $0.ticker == ticker } }

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
        signals.first { $0.impact == .high && !isMuted($0) } ?? signals.first { isAlert($0) }
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
    static func preview() -> MonetaStore {
        let store = MonetaStore.mock()
        Task { await store.start() }
        return store
    }
}
