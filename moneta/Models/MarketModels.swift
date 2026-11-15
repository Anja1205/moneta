import Foundation

// Rows of the Supabase tables the app reads, with explicit snake_case CodingKeys.
// Numeric columns go through `flexibleDouble` (numbers or strings); timestamps stay String and
// are parsed with `BackendDate.parse`.

/// `stocks`: one row per tracked company, shared by all users.
nonisolated struct StockRow: Decodable, Hashable, Sendable {
    let id: UUID
    let ticker: String
    let name: String?
    let domain: String?
    let logoURL: String?
    let brandColor: String?
    let isDemo: Bool
    let price: Double?
    let priceChange: Double?
    let priceChangePct: Double?
    let currency: String?
    let priceUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, ticker, name, domain, price, currency
        case logoURL = "logo_url"
        case brandColor = "brand_color"
        case isDemo = "is_demo"
        case priceChange = "price_change"
        case priceChangePct = "price_change_pct"
        case priceUpdatedAt = "price_updated_at"
    }

    static let columns = "id,ticker,name,domain,logo_url,brand_color,is_demo,price,price_change,price_change_pct,currency,price_updated_at"

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        ticker = try c.decode(String.self, forKey: .ticker).uppercased()
        name = try c.decodeIfPresent(String.self, forKey: .name)
        domain = try c.decodeIfPresent(String.self, forKey: .domain)
        logoURL = try c.decodeIfPresent(String.self, forKey: .logoURL)
        brandColor = try c.decodeIfPresent(String.self, forKey: .brandColor)
        isDemo = (try? c.decodeIfPresent(Bool.self, forKey: .isDemo)) ?? false
        price = c.flexibleDouble(.price)
        priceChange = c.flexibleDouble(.priceChange)
        priceChangePct = c.flexibleDouble(.priceChangePct)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        priceUpdatedAt = try c.decodeIfPresent(String.self, forKey: .priceUpdatedAt)
    }

    var company: Company {
        var company = Company(
            ticker: ticker, name: name ?? ticker,
            brandHex: brandColor.flatMap(UInt32.init(hexString:)) ?? 0xFFB547,
            logoURL: logoURL.flatMap(URL.init(string:)), domain: domain
        )
        company.stockID = id
        return company
    }

    var quote: Quote? {
        guard let price else { return nil }
        return Quote(price: price, previousClose: price - (priceChange ?? 0),
                     updatedAt: priceUpdatedAt.flatMap(BackendDate.parse) ?? .now,
                     currency: (currency?.isEmpty == false ? currency! : "USD").uppercased())
    }
}

/// `watchlist` joined with its stock: `select("stock_id, shares, avg_cost, created_at, stocks(*)")`.
nonisolated struct WatchlistRow: Decodable, Sendable {
    let stockID: UUID
    let shares: Double?
    let avgCost: Double?
    let createdAt: String?
    let stock: StockRow?

    enum CodingKeys: String, CodingKey {
        case shares
        case stockID = "stock_id"
        case avgCost = "avg_cost"
        case createdAt = "created_at"
        case stock = "stocks"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stockID = try c.decode(UUID.self, forKey: .stockID)
        shares = c.flexibleDouble(.shares)
        avgCost = c.flexibleDouble(.avgCost)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        stock = try? c.decodeIfPresent(StockRow.self, forKey: .stock)
    }
}

/// What the user owns of a watched stock. Both nil = only watching.
nonisolated struct Position: Hashable, Sendable {
    var shares: Double?
    var avgCost: Double?

    var isEmpty: Bool { (shares ?? 0) <= 0 }
}

/// A watched stock with its position: a `watchlist` row joined with its `stocks` row.
nonisolated struct Holding: Identifiable, Hashable, Sendable {
    let company: Company
    var position: Position
    var id: String { company.ticker }
}

/// `stock_sentiment` (view): 0 very bearish … 100 very bullish.
nonisolated struct Sentiment: Decodable, Hashable, Sendable {
    let stockID: UUID
    let score: Double
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
        score = c.flexibleDouble(.score) ?? 50
        signals24h = (try? c.decodeIfPresent(Int.self, forKey: .signals24h)) ?? 0
        bullish7d = (try? c.decodeIfPresent(Int.self, forKey: .bullish7d)) ?? 0
        bearish7d = (try? c.decodeIfPresent(Int.self, forKey: .bearish7d)) ?? 0
    }

    init(stockID: UUID, score: Double, signals24h: Int, bullish7d: Int, bearish7d: Int) {
        self.stockID = stockID
        self.score = score
        self.signals24h = signals24h
        self.bullish7d = bullish7d
        self.bearish7d = bearish7d
    }
}

/// `companies` with prices: the Markets tab (rank 1–30).
nonisolated struct MarketCompany: Decodable, Identifiable, Hashable, Sendable {
    let ticker: String
    let name: String
    let domain: String?
    let rank: Int?
    let featured: Bool
    let logoURL: String?
    let brandColor: String?
    let price: Double?
    let priceChange: Double?
    let priceChangePct: Double?
    let currency: String?
    let priceUpdatedAt: String?

    var id: String { ticker }

    enum CodingKeys: String, CodingKey {
        case ticker, name, domain, rank, featured, price, currency
        case logoURL = "logo_url"
        case brandColor = "brand_color"
        case priceChange = "price_change"
        case priceChangePct = "price_change_pct"
        case priceUpdatedAt = "price_updated_at"
    }

    static let columns = "ticker,name,domain,rank,featured,logo_url,brand_color,price,price_change,price_change_pct,currency,price_updated_at"

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try c.decode(String.self, forKey: .ticker).uppercased()
        name = try c.decode(String.self, forKey: .name)
        domain = try c.decodeIfPresent(String.self, forKey: .domain)
        rank = try? c.decodeIfPresent(Int.self, forKey: .rank)
        featured = (try? c.decodeIfPresent(Bool.self, forKey: .featured)) ?? false
        logoURL = try c.decodeIfPresent(String.self, forKey: .logoURL)
        brandColor = try c.decodeIfPresent(String.self, forKey: .brandColor)
        price = c.flexibleDouble(.price)
        priceChange = c.flexibleDouble(.priceChange)
        priceChangePct = c.flexibleDouble(.priceChangePct)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        priceUpdatedAt = try c.decodeIfPresent(String.self, forKey: .priceUpdatedAt)
    }

    var company: Company {
        var company = Company(ticker: ticker, name: name,
                              brandHex: brandColor.flatMap(UInt32.init(hexString:)) ?? Brand.goldHex,
                              logoURL: logoURL.flatMap(URL.init(string:)), domain: domain)
        company.rank = rank
        company.listPrice = price
        company.listChangePct = priceChangePct
        company.listCurrency = currency
        return company
    }

    /// `price_change_pct` is in percent (0.39 = +0.39%); the app's capsules take a fraction.
    var changeFraction: Double? { priceChangePct.map { $0 / 100 } }
}

/// `price_history`: one captured price.
nonisolated struct PriceHistoryRow: Decodable, Sendable {
    let stockID: UUID
    let price: Double?
    let capturedAt: String

    enum CodingKeys: String, CodingKey {
        case price
        case stockID = "stock_id"
        case capturedAt = "captured_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stockID = try c.decode(UUID.self, forKey: .stockID)
        price = c.flexibleDouble(.price)
        capturedAt = try c.decode(String.self, forKey: .capturedAt)
    }

    var point: PricePoint? {
        guard let price, let date = BackendDate.parse(capturedAt) else { return nil }
        return PricePoint(date: date, price: price)
    }
}
