import Foundation
import Observation
import Supabase

let supabase = SupabaseClient(supabaseURL: Config.supabaseURL, supabaseKey: Config.supabaseKey)

private nonisolated struct EmptyBody: Encodable, Sendable {}

@Observable
@MainActor
final class SignalStore {
    private(set) var stocks: [Stock] = []
    private(set) var signals: [Signal] = []
    private(set) var isLive = false
    var errorMessage: String?
    /// Signals that arrived over Realtime this session and haven't been opened yet.
    private(set) var freshIds: Set<UUID> = []
    /// Bumped when a fresh signal at or above `Config.alertImpact` arrives.
    private(set) var alertCount = 0

    var selectedStockID: UUID?
    var minimumImpact = 1
    private(set) var isLoading = false
    private(set) var isPolling = false

    private var channel: RealtimeChannelV2?
    private var listeners: [Task<Void, Never>] = []

    // MARK: Queries

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

    // MARK: Loading

    func start() async {
        await load()
        await startRealtime()
    }

    /// Stocks by `created_at`, last 200 signals by `detected_at` desc.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let stocksQuery: [Stock] = supabase
                .from("stocks")
                .select(Stock.columns)
                .order("created_at")
                .execute()
                .value
            async let signalsQuery: [Signal] = supabase
                .from("signals")
                .select()
                .order("detected_at", ascending: false)
                .limit(200)
                .execute()
                .value
            let (loadedStocks, loadedSignals) = try await (stocksQuery, signalsQuery)
            stocks = loadedStocks
            signals = sorted(loadedSignals)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t load the feed. \(error.localizedDescription)"
        }
    }

    // MARK: Edge Functions

    /// Calls `poll-news`. New rows arrive over Realtime; reloads if Realtime is down.
    func pollNow() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }
        do {
            try await supabase.functions.invoke("poll-news", options: FunctionInvokeOptions(body: EmptyBody()))
            if !isLive { await load() }
        } catch {
            errorMessage = "Polling failed. \(Self.describe(error))"
        }
    }

    /// Calls `add-stock`. Returns `nil` on success, otherwise a message for the form.
    func addStock(ticker: String, name: String, domain: String?) async -> String? {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleanDomain = (domain ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://", "www."] where cleanDomain.hasPrefix(prefix) {
            cleanDomain.removeFirst(prefix.count)
        }
        if let slash = cleanDomain.firstIndex(of: "/") { cleanDomain = String(cleanDomain[..<slash]) }

        guard !cleanTicker.isEmpty, !cleanName.isEmpty else { return "Ticker and name are required." }

        do {
            let response: AddStockResponse = try await supabase.functions.invoke(
                "add-stock",
                options: FunctionInvokeOptions(
                    body: AddStockRequest(ticker: cleanTicker, name: cleanName, domain: cleanDomain.isEmpty ? nil : cleanDomain)
                )
            )
            upsert(response.stock)
            selectedStockID = response.stock.id
            if response.added {
                Task { await pollNow() }
            }
            return nil
        } catch {
            return "Couldn’t add \(cleanTicker). \(Self.describe(error))"
        }
    }

    // MARK: Realtime

    func startRealtime() async {
        guard channel == nil else { return }
        let channel = supabase.channel("moneta-feed")
        let signalChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "signals")
        let stockChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "stocks")
        self.channel = channel

        listeners.append(Task { [weak self] in
            for await change in signalChanges { self?.handleSignal(change) }
        })
        listeners.append(Task { [weak self] in
            for await change in stockChanges { self?.handleStock(change) }
        })
        listeners.append(Task { [weak self] in
            for await status in channel.statusChange { self?.isLive = status == .subscribed }
        })

        do {
            try await channel.subscribeWithError()
        } catch {
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

    private func handleSignal(_ change: AnyAction) {
        let decoder = JSONDecoder()
        switch change {
        case .insert(let action):
            guard let signal = try? action.decodeRecord(as: Signal.self, decoder: decoder) else { return }
            let isFresh = !signals.contains { $0.id == signal.id }
            upsert(signal)
            if isFresh {
                freshIds.insert(signal.id)
                if signal.clampedImpact >= Config.alertImpact { alertCount += 1 }
            }
        case .update(let action):
            guard let signal = try? action.decodeRecord(as: Signal.self, decoder: decoder) else { return }
            upsert(signal)
        case .delete(let action):
            guard let id = action.oldRecord["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else { return }
            signals.removeAll { $0.id == id }
            freshIds.remove(id)
        }
    }

    private func handleStock(_ change: AnyAction) {
        let decoder = JSONDecoder()
        switch change {
        case .insert(let action):
            if let stock = try? action.decodeRecord(as: Stock.self, decoder: decoder) { upsert(stock) }
        case .update(let action):
            if let stock = try? action.decodeRecord(as: Stock.self, decoder: decoder) { upsert(stock) }
        case .delete(let action):
            guard let id = action.oldRecord["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else { return }
            stocks.removeAll { $0.id == id }
            signals.removeAll { $0.stockID == id }
            if selectedStockID == id { selectedStockID = nil }
        }
    }

    // MARK: Helpers

    private func upsert(_ signal: Signal) {
        if let index = signals.firstIndex(where: { $0.id == signal.id }) {
            signals[index] = signal
        } else {
            signals.append(signal)
        }
        signals = sorted(signals)
    }

    private func upsert(_ stock: Stock) {
        if let index = stocks.firstIndex(where: { $0.id == stock.id }) {
            stocks[index] = stock
        } else {
            stocks.append(stock)
        }
    }

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
