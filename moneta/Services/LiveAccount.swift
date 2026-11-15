import Foundation
import Supabase

/// The signed-in user's side of the Moneta backend: their watchlist rows (with positions),
/// sentiment, the Top 30, "fetch news now", and the one Realtime channel ("moneta-live").
/// Only used with the Moneta backend data source; demo mode runs without it.
final class LiveAccount {
    /// What the Realtime channel delivers, already decoded.
    struct Handlers {
        var signalInserted: (WebChange) -> Void
        var signalUpdated: (WebChange) -> Void
        var stockUpdated: (StockRow) -> Void
        var watchlistChanged: () -> Void
        var priceInserted: (PriceHistoryRow) -> Void
        var companyUpdated: (MarketCompany) -> Void
        var liveChanged: (Bool) -> Void
    }

    private var channel: RealtimeChannelV2?
    private var listeners: [Task<Void, Never>] = []

    private var userID: UUID? { supabase.auth.currentUser?.id }

    // MARK: Reads

    /// `watchlist` joined with `stocks`, oldest first.
    func holdings() async throws -> [Holding] {
        let rows: [WatchlistRow] = try await supabase
            .from("watchlist")
            .select("stock_id, shares, avg_cost, created_at, stocks(*)")
            .order("created_at")
            .execute()
            .value
        return rows.compactMap { row in
            guard let stock = row.stock else { return nil }
            return Holding(company: stock.company, position: Position(shares: row.shares, avgCost: row.avgCost))
        }
    }

    /// `stocks` rows (prices) for these ids.
    func stocks(_ ids: [UUID]) async throws -> [StockRow] {
        guard !ids.isEmpty else { return [] }
        return try await supabase
            .from("stocks")
            .select(StockRow.columns)
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value
    }

    /// `stock_sentiment` for these stocks.
    func sentiment(_ ids: [UUID]) async throws -> [Sentiment] {
        guard !ids.isEmpty else { return [] }
        return try await supabase
            .from("stock_sentiment")
            .select("stock_id,score,signals_24h,bullish_7d,bearish_7d")
            .in("stock_id", values: ids.map(\.uuidString))
            .execute()
            .value
    }

    /// `companies` rank 1–30 with prices.
    func topCompanies() async throws -> [MarketCompany] {
        try await supabase
            .from("companies")
            .select(MarketCompany.columns)
            .lte("rank", value: 30)
            .order("rank")
            .execute()
            .value
    }

    /// `price_history` for one stock since `since`, oldest first.
    func priceHistory(_ stockID: UUID, since: Date) async throws -> [PricePoint] {
        let rows: [PriceHistoryRow] = try await supabase
            .from("price_history")
            .select("stock_id,price,captured_at")
            .eq("stock_id", value: stockID.uuidString)
            .gte("captured_at", value: since.formatted(.iso8601))
            .order("captured_at")
            .limit(2000)
            .execute()
            .value
        return rows.compactMap(\.point)
    }

    // MARK: Writes

    /// Sets (or clears, with nils) the position on the user's watchlist row.
    func updatePosition(stockID: UUID, _ position: Position) async throws {
        guard let userID else { throw AuthError.sessionMissing }
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
        try await supabase
            .from("watchlist")
            .update(Patch(shares: position.shares, avgCost: position.avgCost))
            .eq("user_id", value: userID.uuidString)
            .eq("stock_id", value: stockID.uuidString)
            .execute()
    }

    /// Deletes the user's watchlist row.
    func removeFromWatchlist(stockID: UUID) async throws {
        guard let userID else { throw AuthError.sessionMissing }
        try await supabase
            .from("watchlist")
            .delete()
            .eq("user_id", value: userID.uuidString)
            .eq("stock_id", value: stockID.uuidString)
            .execute()
    }

    /// `poll-news`: asks the backend to fetch news now.
    func pollNews() async throws {
        nonisolated struct Empty: Encodable, Sendable {}
        try await supabase.functions.invoke("poll-news", options: FunctionInvokeOptions(body: Empty()))
    }

    // MARK: Realtime

    var isSubscribed: Bool { channel != nil }

    /// One channel for everything. Safe to call again: it does nothing while subscribed.
    func startRealtime(_ handlers: Handlers) async {
        guard channel == nil else { return }
        let channel = supabase.channel("moneta-live")
        let decoder = JSONDecoder()

        // Register every listener before subscribing so no event is missed.
        let signalInserts = channel.postgresChange(InsertAction.self, schema: "public", table: "signals")
        let signalUpdates = channel.postgresChange(UpdateAction.self, schema: "public", table: "signals")
        let stockUpdates = channel.postgresChange(UpdateAction.self, schema: "public", table: "stocks")
        let priceInserts = channel.postgresChange(InsertAction.self, schema: "public", table: "price_history")
        let companyUpdates = channel.postgresChange(UpdateAction.self, schema: "public", table: "companies")
        let watchlistChanges: AsyncStream<AnyAction> = if let userID {
            channel.postgresChange(AnyAction.self, schema: "public", table: "watchlist",
                                   filter: .eq("user_id", value: userID))
        } else {
            channel.postgresChange(AnyAction.self, schema: "public", table: "watchlist")
        }
        self.channel = channel

        listeners = [
            Task {
                for await event in signalInserts {
                    if let row = try? event.decodeRecord(as: BackendSignalRow.self, decoder: decoder),
                       let change = BackendWebMonitorService.change(fromRealtime: row) {
                        handlers.signalInserted(change)
                    }
                }
            },
            Task {
                for await event in signalUpdates {
                    if let row = try? event.decodeRecord(as: BackendSignalRow.self, decoder: decoder),
                       let change = BackendWebMonitorService.change(fromRealtime: row) {
                        handlers.signalUpdated(change)
                    }
                }
            },
            Task {
                for await event in stockUpdates {
                    if let row = try? event.decodeRecord(as: StockRow.self, decoder: decoder) {
                        handlers.stockUpdated(row)
                    }
                }
            },
            Task {
                for await event in priceInserts {
                    if let row = try? event.decodeRecord(as: PriceHistoryRow.self, decoder: decoder) {
                        handlers.priceInserted(row)
                    }
                }
            },
            Task {
                for await event in companyUpdates {
                    if let row = try? event.decodeRecord(as: MarketCompany.self, decoder: decoder) {
                        handlers.companyUpdated(row)
                    }
                }
            },
            Task {
                for await _ in watchlistChanges { handlers.watchlistChanged() }
            },
            Task {
                for await status in channel.statusChange { handlers.liveChanged(status == .subscribed) }
            },
        ]

        do {
            try await channel.subscribeWithError()
        } catch {
            handlers.liveChanged(false)
            await stopRealtime()
        }
    }

    func stopRealtime() async {
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
        if let channel { await supabase.removeChannel(channel) }
        channel = nil
    }
}
