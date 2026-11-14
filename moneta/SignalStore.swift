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
    /// Signals that arrived over Realtime in the last few seconds.
    private(set) var freshIds: Set<UUID> = []
    /// Called for each Realtime INSERT whose `is_new` is true.
    var onNewSignal: ((Signal) -> Void)?

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

    /// One channel: INSERTs on `public.signals`, any change on `public.stocks`.
    func startRealtime() async {
        guard channel == nil else { return }
        let channel = supabase.channel("moneta-live")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "signals")
        let stockChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "stocks")
        self.channel = channel

        listeners.append(Task { [weak self] in
            for await insert in inserts {
                guard let signal = try? insert.decodeRecord(as: Signal.self, decoder: JSONDecoder()) else { continue }
                self?.receive(signal)
            }
        })
        listeners.append(Task { [weak self] in
            for await _ in stockChanges {
                await self?.loadStocks()
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
        guard !signals.contains(where: { $0.id == signal.id }) else { return }
        signals.insert(signal, at: 0)
        freshIds.insert(signal.id)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.freshIds.remove(signal.id)
        }
        if signal.isNew {
            onNewSignal?(signal)
        }
    }

    private func loadStocks() async {
        do {
            stocks = try await supabase
                .from("stocks")
                .select(Stock.columns)
                .order("created_at")
                .execute()
                .value
            if let selectedStockID, !stocks.contains(where: { $0.id == selectedStockID }) {
                self.selectedStockID = nil
            }
        } catch {
            errorMessage = "Couldn’t refresh stocks. \(error.localizedDescription)"
        }
    }

    // MARK: Helpers

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
