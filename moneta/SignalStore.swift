import Foundation
import Observation
import Supabase

let supabase = SupabaseClient(supabaseURL: Config.supabaseURL, supabaseKey: Config.supabaseKey)

private nonisolated struct EmptyBody: Encodable, Sendable {}

/// The signed-in user's watchlist and the signals for those stocks.
@Observable
@MainActor
final class SignalStore {
    /// Stocks on the user's watchlist, in the order they were added.
    private(set) var stocks: [Stock] = []
    /// Signals for watched stocks only, newest first.
    private(set) var signals: [Signal] = []
    /// The user's shares / average cost per watched stock.
    private(set) var holdings: [UUID: Holding] = [:]
    /// Sentiment per watched stock, from the `stock_sentiment` view.
    private(set) var sentiment: [UUID: StockSentiment] = [:]
    /// Price history per stock, oldest first. Loaded on demand by the detail screen.
    private(set) var priceHistory: [UUID: [PricePoint]] = [:]
    private(set) var isRefreshingPrices = false
    /// Stocks whose price just changed over Realtime, with the direction of the move. Cleared after a moment.
    private(set) var priceFlash: [UUID: Direction] = [:]

    /// How much price history the chart shows.
    static let priceHistoryWindow: TimeInterval = 7 * 24 * 3600
    private(set) var isLive = false
    var errorMessage: String?
    /// Signals that arrived over Realtime in the last few seconds.
    private(set) var freshIds: Set<UUID> = []
    /// Called for each Realtime INSERT on a watched stock whose `is_new` is true.
    var onNewSignal: ((Signal) -> Void)?

    var selectedStockID: UUID?
    var minimumImpact = 1
    private(set) var isLoading = false
    private(set) var isPolling = false

    private var channel: RealtimeChannelV2?
    private var listeners: [Task<Void, Never>] = []
    private var sentimentReload: Task<Void, Never>?
    /// Bumped by reset() so a load that finishes after sign-out is discarded.
    private var generation = 0

    // MARK: Queries

    var watchedIds: Set<UUID> { Set(stocks.map(\.id)) }

    var visibleSignals: [Signal] {
        signals.filter { signal in
            (selectedStockID == nil || signal.stockID == selectedStockID) && signal.clampedImpact >= minimumImpact
        }
    }

    func signals(for stock: Stock) -> [Signal] {
        signals.filter { $0.stockID == stock.id }
    }

    func latestSignal(for stock: Stock) -> Signal? {
        signals.first { $0.stockID == stock.id }
    }

    func stock(for signal: Signal) -> Stock? {
        stocks.first { $0.id == signal.stockID }
    }

    func holding(for stock: Stock) -> Holding {
        holdings[stock.id] ?? Holding()
    }

    /// Total market value of positions that have shares and a price, per currency code.
    var portfolioValue: [String: Double] {
        var totals: [String: Double] = [:]
        for stock in stocks {
            if let value = holding(for: stock).marketValue(at: stock.price) {
                totals[stock.currencyCode, default: 0] += value
            }
        }
        return totals
    }

    func isWatching(ticker: String) -> Bool {
        let upper = ticker.uppercased()
        return stocks.contains { $0.ticker.uppercased() == upper }
    }

    // MARK: Loading

    /// The user's watchlist (with each stock, oldest first), then the last 200 signals for those stocks.
    func load() async {
        let started = generation
        isLoading = true
        defer { isLoading = false }

        nonisolated struct WatchRow: Decodable, Sendable {
            let stockID: UUID
            let stock: Stock?
            let holding: Holding
            enum CodingKeys: String, CodingKey {
                case stockID = "stock_id"
                case stock = "stocks"
                case shares
                case avgCost = "avg_cost"
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                stockID = try c.decode(UUID.self, forKey: .stockID)
                stock = try c.decodeIfPresent(Stock.self, forKey: .stock)
                holding = Holding(shares: c.flexibleDouble(.shares), avgCost: c.flexibleDouble(.avgCost))
            }
        }

        do {
            let rows: [WatchRow] = try await supabase
                .from("watchlist")
                .select("stock_id, shares, avg_cost, stocks(\(Stock.columns))")
                .order("created_at")
                .execute()
                .value
            let watched = rows.compactMap(\.stock)

            var loadedSignals: [Signal] = []
            if !watched.isEmpty {
                loadedSignals = try await supabase
                    .from("signals")
                    .select()
                    .in("stock_id", values: watched.map(\.id.uuidString))
                    .order("detected_at", ascending: false)
                    .limit(200)
                    .execute()
                    .value
            }

            let loadedSentiment = await fetchSentiment(for: watched.map(\.id))

            guard started == generation else { return }
            stocks = watched
            holdings = Dictionary(rows.map { ($0.stockID, $0.holding) }, uniquingKeysWith: { _, new in new })
            if let loadedSentiment { sentiment = loadedSentiment }
            signals = sorted(loadedSignals)
            if let selectedStockID, !watchedIds.contains(selectedStockID) {
                self.selectedStockID = nil
            }
            errorMessage = nil
        } catch {
            guard started == generation, !Task.isCancelled else { return }
            errorMessage = "Couldn’t load your watchlist. \(Self.describe(error))"
        }
    }

    /// Sentiment rows for the given stocks, or `nil` if the view couldn't be read (keeps the old values).
    private func fetchSentiment(for ids: [UUID]) async -> [UUID: StockSentiment]? {
        guard !ids.isEmpty else { return [:] }
        do {
            let rows: [StockSentiment] = try await supabase
                .from("stock_sentiment")
                .select("stock_id,score,signals_24h,bullish_7d,bearish_7d")
                .in("stock_id", values: ids.map(\.uuidString))
                .execute()
                .value
            return Dictionary(rows.map { ($0.stockID, $0) }, uniquingKeysWith: { _, new in new })
        } catch {
            return nil
        }
    }

    /// Coalesces bursts of new signals into one `stock_sentiment` read.
    private func scheduleSentimentReload() {
        sentimentReload?.cancel()
        sentimentReload = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.reloadSentiment()
        }
    }

    private func reloadSentiment() async {
        #if DEBUG
        if DemoMode.isMain { return }
        #endif
        let started = generation
        guard let loaded = await fetchSentiment(for: stocks.map(\.id)), started == generation else { return }
        sentiment = loaded
    }

    /// Loads the last 7 days of prices for a stock (stored oldest first, at most 2000 rows).
    func loadPriceHistory(for stock: Stock) async {
        #if DEBUG
        if DemoMode.isMain {
            priceHistory[stock.id] = DemoMode.priceHistory(for: stock)
            return
        }
        #endif
        let started = generation
        do {
            let rows: [PricePoint] = try await supabase
                .from("price_history")
                .select("id,stock_id,price,captured_at")
                .eq("stock_id", value: stock.id)
                .gte("captured_at", value: Date().addingTimeInterval(-Self.priceHistoryWindow).formatted(.iso8601))
                .order("captured_at", ascending: false)
                .limit(2000)
                .execute()
                .value
            guard started == generation else { return }
            priceHistory[stock.id] = rows.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        } catch {
            guard started == generation, !Task.isCancelled else { return }
            errorMessage = "Couldn’t load price history for \(stock.ticker). \(Self.describe(error))"
        }
    }

    // MARK: Holdings

    /// Saves shares / average cost on the user's watchlist row. Pass `nil` to clear a field.
    /// Returns `nil` on success, otherwise a message to show.
    func updateHolding(for stock: Stock, shares: Double?, avgCost: Double?) async -> String? {
        #if DEBUG
        if DemoMode.isMain {
            holdings[stock.id] = Holding(shares: shares, avgCost: avgCost)
            return nil
        }
        #endif
        guard let userID = supabase.auth.currentUser?.id else {
            return "You’re signed out. Sign in to save your position."
        }
        nonisolated struct Patch: Encodable, Sendable {
            let shares: Double?
            let avgCost: Double?
            enum CodingKeys: String, CodingKey {
                case shares
                case avgCost = "avg_cost"
            }
            // Encode nil as JSON null so a cleared field is cleared in the database.
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(shares, forKey: .shares)
                try c.encode(avgCost, forKey: .avgCost)
            }
        }
        do {
            try await supabase
                .from("watchlist")
                .update(Patch(shares: shares, avgCost: avgCost))
                .eq("user_id", value: userID)
                .eq("stock_id", value: stock.id)
                .execute()
            holdings[stock.id] = Holding(shares: shares, avgCost: avgCost)
            return nil
        } catch {
            return "Couldn’t save your \(stock.ticker) position. \(Self.describe(error))"
        }
    }

    // MARK: Edge Functions

    /// Pull-to-refresh: news, page changes and prices at once. Reloads afterwards if Realtime is down.
    func refreshAll() async {
        async let news: Void = pollNow(reloadIfOffline: false)
        async let pages: Void = watchPages()
        async let prices: Void = refreshPrices(reloadIfOffline: false)
        _ = await (news, pages, prices)
        if !isLive { await load() } else { await reloadSentiment() }
    }

    /// Calls `refresh-prices`, for one ticker or (nil) every stock. New prices arrive over Realtime.
    func refreshPrices(ticker: String? = nil, reloadIfOffline: Bool = true) async {
        guard !isRefreshingPrices else { return }
        isRefreshingPrices = true
        defer { isRefreshingPrices = false }
        nonisolated struct Body: Encodable, Sendable { let ticker: String? }
        do {
            try await supabase.functions.invoke(
                "refresh-prices", options: FunctionInvokeOptions(body: Body(ticker: ticker?.uppercased()))
            )
            if reloadIfOffline, !isLive { await load() }
        } catch {
            errorMessage = "Couldn’t refresh prices. \(Self.describe(error))"
        }
    }

    /// Calls `watch-pages` with `{force: true}`. Page-change signals arrive over Realtime.
    func watchPages() async {
        nonisolated struct Body: Encodable, Sendable { let force = true }
        do {
            try await supabase.functions.invoke("watch-pages", options: FunctionInvokeOptions(body: Body()))
        } catch {
            errorMessage = "Couldn’t check company pages. \(Self.describe(error))"
        }
    }

    /// Calls `poll-news`. New rows arrive over Realtime; reloads if Realtime is down.
    func pollNow(reloadIfOffline: Bool = true) async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }
        do {
            try await supabase.functions.invoke("poll-news", options: FunctionInvokeOptions(body: EmptyBody()))
            if reloadIfOffline, !isLive { await load() }
        } catch {
            errorMessage = "Polling failed. \(Self.describe(error))"
        }
    }

    /// Calls `add-stock` with `{ticker, name, domain}`; the function also adds it to the user's watchlist.
    /// Returns `nil` on success, otherwise a message to show.
    func addStock(ticker: String, name: String? = nil, domain: String? = nil) async -> String? {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else { return "Pick a company first." }
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDomain = domain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        do {
            let response = try await MonetaAPI.addStock(
                ticker: cleanTicker,
                name: cleanName?.isEmpty == false ? cleanName : nil,
                domain: cleanDomain?.isEmpty == false ? cleanDomain : nil
            )
            guard response.watching ?? true else {
                return "Couldn’t add \(cleanTicker) to your watchlist. Please sign in again."
            }
            if !stocks.contains(where: { $0.id == response.stock.id }) {
                stocks.append(response.stock)
            }
            // Pull in any signals the stock already has.
            Task { await load() }
            if response.added {
                Task { await pollNow() }
                Task { await refreshPrices(ticker: response.stock.ticker) }
            }
            return nil
        } catch {
            return "Couldn’t add \(cleanTicker). \(Self.describe(error))"
        }
    }

    /// Removes the stock from the signed-in user's watchlist.
    func removeStock(_ stock: Stock) async {
        guard let userID = supabase.auth.currentUser?.id else {
            errorMessage = "You’re signed out. Sign in to change your watchlist."
            return
        }
        do {
            try await supabase
                .from("watchlist")
                .delete()
                .eq("user_id", value: userID)
                .eq("stock_id", value: stock.id)
                .execute()
            stocks.removeAll { $0.id == stock.id }
            signals.removeAll { $0.stockID == stock.id }
            holdings[stock.id] = nil
            sentiment[stock.id] = nil
            priceHistory[stock.id] = nil
            freshIds = freshIds.filter { id in signals.contains { $0.id == id } }
            if selectedStockID == stock.id { selectedStockID = nil }
        } catch {
            errorMessage = "Couldn’t remove \(stock.ticker). \(Self.describe(error))"
        }
    }

    /// Clears everything and stops Realtime. Call on sign-out.
    func reset() async {
        generation += 1
        sentimentReload?.cancel()
        await stopRealtime()
        stocks = []
        signals = []
        holdings = [:]
        sentiment = [:]
        priceHistory = [:]
        priceFlash = [:]
        isRefreshingPrices = false
        freshIds = []
        selectedStockID = nil
        minimumImpact = 1
        errorMessage = nil
        isLoading = false
        isPolling = false
    }

    // MARK: Realtime

    /// One channel: signal INSERTs (kept only for watched stocks), changes to watched stocks,
    /// and the user's own watchlist rows (reload on any change).
    func startRealtime() async {
        guard channel == nil else { return }
        let channel = supabase.channel("moneta-live")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "signals")
        let stockChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "stocks")
        let priceInserts = channel.postgresChange(InsertAction.self, schema: "public", table: "price_history")
        let watchlistChanges: AsyncStream<AnyAction>
        if let userID = supabase.auth.currentUser?.id {
            watchlistChanges = channel.postgresChange(
                AnyAction.self, schema: "public", table: "watchlist", filter: .eq("user_id", value: userID)
            )
        } else {
            watchlistChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "watchlist")
        }
        self.channel = channel

        listeners.append(Task { [weak self] in
            for await insert in inserts {
                guard let signal = try? insert.decodeRecord(as: Signal.self, decoder: JSONDecoder()) else { continue }
                self?.receive(signal)
            }
        })
        listeners.append(Task { [weak self] in
            for await change in stockChanges {
                self?.handleStock(change)
            }
        })
        listeners.append(Task { [weak self] in
            for await insert in priceInserts {
                guard let point = try? insert.decodeRecord(as: PricePoint.self, decoder: JSONDecoder()) else { continue }
                self?.receive(point)
            }
        })
        listeners.append(Task { [weak self] in
            for await _ in watchlistChanges {
                await self?.load()
            }
        })
        listeners.append(Task { [weak self] in
            for await status in channel.statusChange {
                self?.isLive = status == .subscribed
            }
        })

        do {
            try await channel.subscribeWithError()
        } catch {
            isLive = false
            errorMessage = "Live updates unavailable. \(error.localizedDescription)"
        }
    }

    func stopRealtime() async {
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
        if let channel { await supabase.removeChannel(channel) }
        channel = nil
        isLive = false
    }

    func markSeen(_ signal: Signal) {
        freshIds.remove(signal.id)
    }

    private func receive(_ signal: Signal) {
        guard watchedIds.contains(signal.stockID),
              !signals.contains(where: { $0.id == signal.id }) else { return }
        signals.insert(signal, at: 0)
        freshIds.insert(signal.id)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.freshIds.remove(signal.id)
        }
        if signal.isNew {
            onNewSignal?(signal)
        }
        scheduleSentimentReload()
    }

    /// Appends a Realtime price to a history that's already loaded.
    private func receive(_ point: PricePoint) {
        guard var history = priceHistory[point.stockID], !history.contains(where: { $0.id == point.id }) else { return }
        history.append(point)
        history.sort { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        let cutoff = Date().addingTimeInterval(-Self.priceHistoryWindow)
        history.removeAll { ($0.date ?? .distantPast) < cutoff }
        if history.count > 2000 { history.removeFirst(history.count - 2000) }
        priceHistory[point.stockID] = history
    }

    /// Keeps watched stocks' details (logo, brand colour, price, last polled) current.
    private func handleStock(_ change: AnyAction) {
        let decoder = JSONDecoder()
        let updated: Stock?
        switch change {
        case .insert(let action): updated = try? action.decodeRecord(as: Stock.self, decoder: decoder)
        case .update(let action): updated = try? action.decodeRecord(as: Stock.self, decoder: decoder)
        case .delete: updated = nil
        }
        guard let updated else { return }
        apply(updated)
    }

    /// Replaces a watched stock with a newer copy and flashes its price if it moved.
    private func apply(_ updated: Stock) {
        guard let index = stocks.firstIndex(where: { $0.id == updated.id }) else { return }
        let old = stocks[index]
        stocks[index] = updated
        if let before = old.price, let after = updated.price, before != after {
            flash(updated.id, after > before ? .bullish : .bearish)
        }
    }

    private func flash(_ id: UUID, _ direction: Direction) {
        priceFlash[id] = direction
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if self?.priceFlash[id] == direction { self?.priceFlash[id] = nil }
        }
    }

    #if DEBUG
    /// Fills the store with local sample data for `-MonetaDemo main`. No network.
    func seedDemo() {
        stocks = DemoMode.stocks()
        signals = sorted(DemoMode.signals(for: stocks))
        sentiment = DemoMode.sentiment()
        holdings = DemoMode.holdings()
        isLive = true
        if let first = signals.first {
            freshIds = [first.id]
        }
        // Simulated Realtime price ticks so the flash and live chart can be checked offline.
        listeners.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                self?.demoTick()
            }
        })
    }

    private func demoTick() {
        let priced = stocks.filter { $0.price != nil }
        guard var stock = priced.randomElement(), let price = stock.price else { return }
        let delta = price * Double.random(in: -0.004...0.004)
        stock.price = price + delta
        stock.priceChange = (stock.priceChange ?? 0) + delta
        let previous = price - (stock.priceChange ?? 0) + delta
        stock.priceChangePct = previous > 0 ? (stock.priceChange ?? 0) / previous * 100 : nil
        stock.priceUpdatedAt = Date().formatted(.iso8601)
        apply(stock)
        if priceHistory[stock.id] != nil, let newPrice = stock.price {
            receive(DemoMode.point(stockID: stock.id, price: newPrice, date: .now))
        }
    }
    #endif

    // MARK: Helpers

    private func sorted(_ list: [Signal]) -> [Signal] {
        list.sorted { ($0.detectedDate ?? .distantPast) > ($1.detectedDate ?? .distantPast) }
    }

    private static func describe(_ error: Error) -> String {
        if case let FunctionsError.httpError(code, data) = error {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return body.isEmpty ? "Server returned \(code)." : "Server returned \(code): \(body.prefix(160))"
        }
        return error.localizedDescription
    }
}
