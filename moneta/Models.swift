import Foundation

nonisolated struct Stock: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ticker: String
    let name: String
    let domain: String?
    let logoURL: String?
    let brandColor: String?
    let lastPolledAt: String?
    let createdAt: String
    // `var` so a Realtime/demo price tick can update a copy in place.
    var price: Double?
    var priceChange: Double?
    var priceChangePct: Double?
    let currency: String?
    var priceUpdatedAt: String?
    let isDemo: Bool

    enum CodingKeys: String, CodingKey {
        case id, ticker, name, domain, price, currency
        case logoURL = "logo_url"
        case brandColor = "brand_color"
        case lastPolledAt = "last_polled_at"
        case createdAt = "created_at"
        case priceChange = "price_change"
        case priceChangePct = "price_change_pct"
        case priceUpdatedAt = "price_updated_at"
        case isDemo = "is_demo"
    }

    static let columns = "id,ticker,name,domain,logo_url,brand_color,last_polled_at,created_at,"
        + "price,price_change,price_change_pct,currency,price_updated_at,is_demo"

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        ticker = try c.decode(String.self, forKey: .ticker)
        name = try c.decode(String.self, forKey: .name)
        domain = try c.decodeIfPresent(String.self, forKey: .domain)
        logoURL = try c.decodeIfPresent(String.self, forKey: .logoURL)
        brandColor = try c.decodeIfPresent(String.self, forKey: .brandColor)
        lastPolledAt = try c.decodeIfPresent(String.self, forKey: .lastPolledAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        price = c.flexibleDouble(.price)
        priceChange = c.flexibleDouble(.priceChange)
        priceChangePct = c.flexibleDouble(.priceChangePct)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        priceUpdatedAt = try c.decodeIfPresent(String.self, forKey: .priceUpdatedAt)
        isDemo = c.flexibleBool(.isDemo) ?? false
    }

    var priceUpdatedDate: Date? { priceUpdatedAt.flatMap(DateParser.parse) }

    /// No price update for more than 30 minutes: treat the market as closed.
    func isMarketClosed(now: Date = .now) -> Bool {
        guard let updated = priceUpdatedDate else { return false }
        return now.timeIntervalSince(updated) > 30 * 60
    }
    /// ISO 4217 code for formatting; USD when the backend sent none.
    var currencyCode: String { (currency?.isEmpty == false ? currency! : "USD").uppercased() }
    /// Direction of today's move, for colouring.
    var priceDirection: Direction {
        guard let change = priceChangePct ?? priceChange, change != 0 else { return .neutral }
        return change > 0 ? .bullish : .bearish
    }
}

/// One row of `price_history`.
nonisolated struct PricePoint: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    let stockID: UUID
    let price: Double
    let capturedAt: String

    enum CodingKeys: String, CodingKey {
        case id, price
        case stockID = "stock_id"
        case capturedAt = "captured_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        stockID = try c.decode(UUID.self, forKey: .stockID)
        guard let value = c.flexibleDouble(.price) else {
            throw DecodingError.dataCorruptedError(forKey: .price, in: c, debugDescription: "Missing price")
        }
        price = value
        capturedAt = try c.decode(String.self, forKey: .capturedAt)
    }

    var date: Date? { DateParser.parse(capturedAt) }
}

/// One row of the `stock_sentiment` view. `score`: 0 very bearish, 50 neutral, 100 very bullish.
nonisolated struct StockSentiment: Decodable, Hashable, Sendable {
    let stockID: UUID
    let score: Int
    let signals24h: Int
    let bullish7d: Int
    let bearish7d: Int

    enum CodingKeys: String, CodingKey {
        case score
        case stockID = "stock_id"
        case signals24h = "signals_24h"
        case bullish7d = "bullish_7d"
        case bearish7d = "bearish_7d"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stockID = try c.decode(UUID.self, forKey: .stockID)
        score = min(max(c.flexibleInt(.score) ?? 50, 0), 100)
        signals24h = c.flexibleInt(.signals24h) ?? 0
        bullish7d = c.flexibleInt(.bullish7d) ?? 0
        bearish7d = c.flexibleInt(.bearish7d) ?? 0
    }

    /// 0–25 Very bearish, 26–45 Bearish, 46–55 Neutral, 56–75 Bullish, 76–100 Very bullish.
    var label: String {
        switch score {
        case ...25: "Very bearish"
        case ...45: "Bearish"
        case ...55: "Neutral"
        case ...75: "Bullish"
        default: "Very bullish"
        }
    }

    var direction: Direction {
        switch score {
        case ...45: .bearish
        case ...55: .neutral
        default: .bullish
        }
    }

    /// "12 signals in 24h · 5 bullish · 3 bearish (7d)"
    var summary: String {
        "\(signals24h) \(signals24h == 1 ? "signal" : "signals") in 24h · \(bullish7d) bullish · \(bearish7d) bearish (7d)"
    }
}

/// The user's position in a watched stock (`watchlist.shares`, `watchlist.avg_cost`).
nonisolated struct Holding: Hashable, Sendable {
    var shares: Double?
    var avgCost: Double?

    var isEmpty: Bool { (shares ?? 0) == 0 }

    func marketValue(at price: Double?) -> Double? {
        guard let shares, shares != 0, let price else { return nil }
        return shares * price
    }

    func gain(at price: Double?) -> Double? {
        guard let shares, shares != 0, let price, let avgCost else { return nil }
        return shares * (price - avgCost)
    }

    /// Total gain/loss in percent: market value vs shares × avg_cost.
    func gainPct(at price: Double?) -> Double? {
        guard let price, let avgCost, avgCost != 0, !isEmpty else { return nil }
        return (price - avgCost) / avgCost * 100
    }

    /// shares × avg_cost.
    var costBasis: Double? {
        guard let shares, shares != 0, let avgCost else { return nil }
        return shares * avgCost
    }

    /// Today's move on the position: shares × price_change.
    func todayChange(_ priceChange: Double?) -> Double? {
        guard let shares, shares != 0, let priceChange else { return nil }
        return shares * priceChange
    }
}

/// Numeric columns may arrive as JSON numbers or strings (Postgres `numeric`); these accept both.
nonisolated extension KeyedDecodingContainer {
    func flexibleDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value.isFinite ? value : nil }
        if let raw = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let value = Double(trimmed), value.isFinite { return value }
        }
        return nil
    }

    func flexibleInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        return flexibleDouble(key).map { Int($0.rounded()) }
    }

    func flexibleBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let raw = try? decodeIfPresent(String.self, forKey: key) {
            switch raw.lowercased() {
            case "true", "t", "1", "yes": return true
            case "false", "f", "0", "no": return false
            default: return nil
            }
        }
        return flexibleInt(key).map { $0 != 0 }
    }
}

nonisolated enum SourceKind: String, Codable, Sendable {
    case news
    case irPage = "ir_page"
    case careers
    case pricing
    case demo
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SourceKind(rawValue: raw) ?? .unknown
    }

    /// A change detected on a watched web page rather than a news story.
    var isPageChange: Bool {
        switch self {
        case .irPage, .demo, .careers, .pricing: true
        case .news, .unknown: false
        }
    }

    var label: String {
        switch self {
        case .news: "News"
        // Backend-generated page changes ("demo") read exactly like investor page changes.
        case .irPage, .demo: "Investor page"
        case .careers: "Careers"
        case .pricing: "Pricing"
        case .unknown: "Web"
        }
    }

    var symbol: String {
        switch self {
        case .news: "newspaper"
        case .irPage, .demo: "building.columns"
        case .careers: "person.2"
        case .pricing: "tag"
        case .unknown: "globe"
        }
    }
}

nonisolated enum Direction: String, Codable, Sendable {
    case bullish, bearish, neutral

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Direction(rawValue: raw) ?? .neutral
    }

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .bullish: "arrow.up.right"
        case .bearish: "arrow.down.right"
        case .neutral: "arrow.right"
        }
    }
}

nonisolated struct Signal: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let stockID: UUID
    let storyID: String
    let ticker: String
    let stockName: String
    let sourceKind: SourceKind
    let title: String
    let description: String?
    let url: String?
    let imageURL: String?
    let sourceName: String?
    let publishedAt: String?
    let detectedAt: String
    let impact: Int
    let direction: Direction
    let why: String
    let isNew: Bool

    enum CodingKeys: String, CodingKey {
        case id, ticker, title, description, url, impact, direction, why
        case stockID = "stock_id"
        case storyID = "story_id"
        case stockName = "stock_name"
        case sourceKind = "source_kind"
        case imageURL = "image_url"
        case sourceName = "source_name"
        case publishedAt = "published_at"
        case detectedAt = "detected_at"
        case isNew = "is_new"
    }

    var detectedDate: Date? { DateParser.parse(detectedAt) }
    var publishedDate: Date? { publishedAt.flatMap(DateParser.parse) }
    /// Best timestamp for display and sorting.
    var displayDate: Date { publishedDate ?? detectedDate ?? .distantPast }
    var clampedImpact: Int { min(max(impact, 1), 5) }
}

/// Body for the `add-stock` function. Only `ticker` is required; nil fields are omitted.
nonisolated struct AddStockRequest: Encodable, Sendable {
    let ticker: String
    var name: String? = nil
    var domain: String? = nil
}

nonisolated struct AddStockResponse: Decodable, Sendable {
    let stock: Stock
    let added: Bool
    /// True when the stock is now on the signed-in user's watchlist.
    let watching: Bool?
}

/// A row of the public `companies` table (featured = the Top 20).
nonisolated struct Company: Codable, Identifiable, Hashable, Sendable {
    let ticker: String
    let name: String
    let domain: String?
    let rank: Int?
    let featured: Bool
    let logoURL: String?
    let brandColor: String?

    enum CodingKeys: String, CodingKey {
        case ticker, name, domain, rank, featured
        case logoURL = "logo_url"
        case brandColor = "brand_color"
    }

    var id: String { ticker }
}

/// Logo fields of a `companies` row.
nonisolated struct CompanyBranding: Decodable, Hashable, Sendable {
    let ticker: String
    let logoURL: String?
    let brandColor: String?

    enum CodingKeys: String, CodingKey {
        case ticker
        case logoURL = "logo_url"
        case brandColor = "brand_color"
    }
}

/// One hit from the `search-companies` function.
nonisolated struct CompanySearchResult: Codable, Identifiable, Hashable, Sendable {
    let ticker: String
    let name: String
    let domain: String?
    let source: String?

    var id: String { ticker }
}

nonisolated struct CompanySearchResponse: Decodable, Sendable {
    let results: [CompanySearchResult]
}

/// Parses the ISO-8601 variants Postgres/PostgREST/Realtime emit:
/// `2026-11-14T14:02:01.826+00:00`, `2026-11-14 14:02:01.662326+00`, `...Z`, no fraction, no zone.
nonisolated enum DateParser {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard s.count >= 19 else { return nil }

        // Date/time separator.
        if s.count > 10 {
            let i = s.index(s.startIndex, offsetBy: 10)
            if s[i] == " " { s.replaceSubrange(i...i, with: "T") }
        }

        // Split into "yyyy-MM-ddTHH:mm:ss", optional fraction, optional zone.
        let base = String(s.prefix(19))
        var rest = Substring(s.dropFirst(19))

        var fraction = ""
        if rest.first == "." {
            rest = rest.dropFirst()
            let digits = rest.prefix { $0.isNumber }
            fraction = String(digits.prefix(3))
            while fraction.count < 3 { fraction += "0" }
            rest = rest.dropFirst(digits.count)
        }

        var zone = String(rest)
        if zone.isEmpty || zone == "Z" || zone == "z" {
            zone = "Z"
        } else if zone.first == "+" || zone.first == "-" {
            let sign = zone.removeFirst()
            let digits = zone.filter(\.isNumber)
            switch digits.count {
            case 2: zone = "\(sign)\(digits):00"
            case 4: zone = "\(sign)\(digits.prefix(2)):\(digits.suffix(2))"
            default: return nil
            }
        } else {
            return nil
        }

        if fraction.isEmpty {
            return plain.date(from: base + zone)
        }
        return withFraction.date(from: "\(base).\(fraction)\(zone)")
    }
}
