#if DEBUG
import SwiftUI

/// DEBUG-only UI demo for layout checks without an account.
///
/// Launch with `-MonetaDemo main` (tabs with sample data), `-MonetaDemo onboarding` or `-MonetaDemo auth`.
/// Nothing is sent to the backend in `main`; the store is filled locally.
enum DemoMode {
    static var route: String? {
        UserDefaults.standard.string(forKey: "MonetaDemo")?.lowercased()
    }

    static var isMain: Bool { route == "main" }

    /// `-MonetaDemoScreen watchlist|feed|alerts|stock|stock2|callout|signal|position|search`, optionally with
    /// a `-bottom` suffix to start scrolled to the end.
    static var screen: String {
        let raw = UserDefaults.standard.string(forKey: "MonetaDemoScreen")?.lowercased() ?? "watchlist"
        return raw.replacingOccurrences(of: "-bottom", with: "").replacingOccurrences(of: "-mid", with: "").replacingOccurrences(of: "-low", with: "")
    }

    static var startAtBottom: Bool {
        isMain && (UserDefaults.standard.string(forKey: "MonetaDemoScreen")?.hasSuffix("-bottom") ?? false)
    }

    /// Scroll anchor for screenshot runs; nil (normal) outside them.
    static var scrollAnchor: UnitPoint? {
        guard isMain else { return nil }
        let raw = UserDefaults.standard.string(forKey: "MonetaDemoScreen") ?? ""
        if raw.hasSuffix("-bottom") { return .bottom }
        if raw.hasSuffix("-mid") { return UnitPoint(x: 0.5, y: 0.3) }
        if raw.hasSuffix("-low") { return UnitPoint(x: 0.5, y: 0.52) }
        return nil
    }

    private static func iso(_ minutesAgo: Double) -> String {
        Date().addingTimeInterval(-minutesAgo * 60).formatted(.iso8601)
    }

    static let stockIDs: [UUID] = (0..<6).map { _ in UUID() }

    static func stocks() -> [Stock] {
        let rows: [(String, String, String?, String?, String, String, String, String?, Bool)] = [
            // ticker, name, logo, brand, price, change, pct, currency, demo
            ("AAPL", "Apple Inc.", "https://github.githubassets.com/favicons/favicon.png", "#A2AAAD", "\"228.52\"", "3.41", "1.51", "USD", false),
            ("TSM", "Taiwan Semiconductor Manufacturing Company Limited", nil, "#C8102E", "187.06", "-4.92", "-2.56", "USD", false),
            ("BRK.A", "Berkshire Hathaway Inc. Class A", nil, "#1F3A93", "712345.67", "-1250.5", "-0.17", "USD", false),
            ("SPOT", "Spotify Technology S.A.", "https://example.com/logo.svg", "#1DB954", "\"612.3\"", "\"0\"", "\"0\"", "USD", true),
            ("NOKIA", "Nokia Oyj", nil, nil, "4.1234", "0.0812", "2.01", "EUR", false),
            ("NEWCO", "Newly Listed Company With No Price Yet", nil, "#8E44AD", "null", "null", "null", nil, false),
        ]
        let json = rows.enumerated().map { index, row in
            """
            {"id":"\(stockIDs[index].uuidString)","ticker":"\(row.0)","name":"\(row.1)","domain":null,
             "logo_url":\(row.2.map { "\"\($0)\"" } ?? "null"),"brand_color":\(row.3.map { "\"\($0)\"" } ?? "null"),
             "last_polled_at":"\(iso(3))","created_at":"\(iso(9000))",
             "price":\(row.4),"price_change":\(row.5),"price_change_pct":\(row.6),
             "currency":\(row.7.map { "\"\($0)\"" } ?? "null"),"price_updated_at":"\(iso(index == 2 ? 45 : Double(index * 7 + 1)))",
             "is_demo":\(row.8)}
            """
        }.joined(separator: ",")
        return (try? JSONDecoder().decode([Stock].self, from: Data("[\(json)]".utf8))) ?? []
    }

    static func signals(for stocks: [Stock]) -> [Signal] {
        let samples: [(Int, String, Int, String, String, String, Double)] = [
            (0, "news", 5, "bullish", "Apple wins approval for satellite messaging in 40 new markets",
             "Regulators cleared the service ahead of the holiday quarter, which widens the iPhone's lead in emergency features and could lift upgrade demand.", 0.3),
            (1, "ir_page", 4, "bearish", "TSMC investor page adds a note on delayed 2nm ramp",
             "A quiet edit to the investor relations FAQ pushes volume 2nm production by a quarter. Margins may dip while Arizona capacity comes online.", 12),
            (2, "news", 2, "neutral", "Berkshire annual letter date announced",
             "No new information yet; the date matches previous years.", 95),
            (3, "demo", 3, "bullish", "Spotify pricing page shows a new family tier",
             "A cheaper family plan in three markets suggests a push for subscriber growth before the next earnings call.", 240),
            (4, "news", 4, "bullish", "Nokia signs a five-year 5G deal with a major European carrier",
             "The contract is one of the largest this year and secures recurring revenue in its network infrastructure unit, which investors had worried about.", 600),
            (0, "news", 1, "neutral", "Apple updates its developer documentation",
             "Routine change.", 1440),
        ]
        return samples.map { index, kind, impact, direction, title, why, minutes in
            let stock = stocks[index]
            let json = """
            {"id":"\(UUID().uuidString)","stock_id":"\(stock.id.uuidString)","story_id":"\(UUID().uuidString)",
             "ticker":"\(stock.ticker)","stock_name":"\(stock.name)","source_kind":"\(kind)","title":"\(title)",
             "description":"A longer description of the story so the detail screen has something to wrap across several lines on small phones.",
             "url":"https://example.com/story","image_url":null,"source_name":\(kind == "news" ? "\"Reuters\"" : "null"),
             "published_at":"\(iso(minutes + 2))","detected_at":"\(iso(minutes))","impact":\(impact),
             "direction":"\(direction)","why":"\(why)","is_new":true}
            """
            return try! JSONDecoder().decode(Signal.self, from: Data(json.utf8))
        }
    }

    static func sentiment() -> [UUID: StockSentiment] {
        let scores = [82, 18, 50, 64, 71, 50]
        var map: [UUID: StockSentiment] = [:]
        for (index, id) in stockIDs.enumerated() {
            let json = """
            {"stock_id":"\(id.uuidString)","score":"\(scores[index])","signals_24h":\(index + 1),"bullish_7d":\(index * 3),"bearish_7d":"\(index)"}
            """
            map[id] = try? JSONDecoder().decode(StockSentiment.self, from: Data(json.utf8))
        }
        return map
    }

    static func holdings() -> [UUID: Holding] {
        [
            stockIDs[0]: Holding(shares: 25, avgCost: 151.2),
            stockIDs[1]: Holding(shares: 120.5, avgCost: 201.33),
            stockIDs[2]: Holding(shares: 1, avgCost: 540000),
        ]
    }

    /// Seven days, one point every two hours, ending at the current price.
    static func priceHistory(for stock: Stock) -> [PricePoint] {
        guard let price = stock.price else { return [] }
        let steps = 84
        let trend = (stock.priceChangePct ?? 0) >= 0 ? 1.0 : -1.0
        return (0...steps).map { step in
            let remaining = Double(steps - step)
            let wave = sin(Double(step) / 7) * price * 0.012 - trend * remaining * price * 0.0006
            return point(stockID: stock.id, price: price + wave, date: Date().addingTimeInterval(-remaining * 7200))
        }
    }

    static func point(stockID: UUID, price: Double, date: Date) -> PricePoint {
        let json = """
        {"id":"\(UUID().uuidString)","stock_id":"\(stockID.uuidString)","price":\(price),"captured_at":"\(date.formatted(.iso8601))"}
        """
        return try! JSONDecoder().decode(PricePoint.self, from: Data(json.utf8))
    }
}
#endif

import SwiftUI

extension View {
    /// DEBUG screenshot runs only: start the scroll view at the bottom when asked.
    func demoScrollAnchor() -> some View {
        #if DEBUG
        return defaultScrollAnchor(DemoMode.scrollAnchor)
        #else
        return self
        #endif
    }
}
