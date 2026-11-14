import Foundation

/// Real market data from the Moneta backend (Supabase):
/// - search: `companies` (Top 20) and the `search-companies` function
/// - quotes: the `stocks` table, filled by the `refresh-prices` function (Context.dev on the server)
/// - history: the `price_history` table
/// - tracking: the `add-stock` function
final class BackendPriceService: PriceService {
    private let client: BackendClient
    /// ticker → stocks.id, for price_history lookups.
    private var stockIDs: [String: UUID] = [:]
    /// How often live quotes are re-read, and how often the backend is asked for fresh prices.
    private let pollInterval: Duration = .seconds(15)
    private let refreshEvery = 20 // polls (≈ 5 minutes)

    init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    // MARK: Search

    func searchCompanies(_ query: String) async throws -> [Company] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return try await featured() }

        struct Body: Encodable { let query: String }
        struct Response: Decodable {
            struct Hit: Decodable { let ticker: String; let name: String; let domain: String? }
            let results: [Hit]
        }
        let response: Response = try await client.invoke("search-companies", body: Body(query: q))
        var seen = Set<String>()
        let hits = response.results.filter { seen.insert($0.ticker.uppercased()).inserted }
        let branding = try? await branding(for: hits.map { $0.ticker.uppercased() })
        return hits.map { hit in
            let ticker = hit.ticker.uppercased()
            var company = Company(ticker: ticker, name: hit.name, domain: hit.domain)
            if let brand = branding?[ticker] {
                company.logoURL = brand.logoURL
                company.brandHex = brand.brandHex ?? company.brandHex
            }
            return company
        }
    }

    private struct CompanyRow: Decodable {
        let ticker: String
        let name: String
        let domain: String?
        let logo_url: String?
        let brand_color: String?

        var company: Company {
            Company(
                ticker: ticker.uppercased(), name: name,
                brandHex: brand_color.flatMap(UInt32.init(hexString:)) ?? 0xFFB547,
                logoURL: logo_url.flatMap(URL.init(string:)), domain: domain
            )
        }
        var logoURL: URL? { logo_url.flatMap(URL.init(string:)) }
        var brandHex: UInt32? { brand_color.flatMap(UInt32.init(hexString:)) }
    }

    private func featured() async throws -> [Company] {
        let rows: [CompanyRow] = try await client.select("companies", query: [
            URLQueryItem(name: "select", value: "ticker,name,domain,logo_url,brand_color"),
            URLQueryItem(name: "featured", value: "eq.true"),
            URLQueryItem(name: "order", value: "rank"),
        ])
        return rows.map(\.company)
    }

    private func branding(for tickers: [String]) async throws -> [String: CompanyRow] {
        guard !tickers.isEmpty else { return [:] }
        let rows: [CompanyRow] = try await client.select("companies", query: [
            URLQueryItem(name: "select", value: "ticker,name,domain,logo_url,brand_color"),
            URLQueryItem(name: "ticker", value: "in.(\(tickers.joined(separator: ",")))"),
        ])
        return Dictionary(rows.map { ($0.ticker.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    func defaultWatchlist() async -> [Company] {
        Array(((try? await featured()) ?? []).prefix(4))
    }

    // MARK: Quotes

    private struct StockRow: Decodable {
        let id: UUID
        let ticker: String
        let price: Double?
        let change: Double?
        let currency: String?
        let updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, ticker, price, currency
            case change = "price_change"
            case updatedAt = "price_updated_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            ticker = try c.decode(String.self, forKey: .ticker)
            price = c.flexibleDouble(.price)
            change = c.flexibleDouble(.change)
            currency = try c.decodeIfPresent(String.self, forKey: .currency)
            updatedAt = (try c.decodeIfPresent(String.self, forKey: .updatedAt)).flatMap(BackendDate.parse)
        }

        var quote: Quote? {
            guard let price else { return nil }
            return Quote(price: price, previousClose: price - (change ?? 0), updatedAt: updatedAt ?? .now,
                         currency: (currency?.isEmpty == false ? currency! : "USD").uppercased())
        }
    }

    private func stocks(_ tickers: [String]) async throws -> [StockRow] {
        guard !tickers.isEmpty else { return [] }
        let rows: [StockRow] = try await client.select("stocks", query: [
            URLQueryItem(name: "select", value: "id,ticker,price,price_change,currency,price_updated_at"),
            URLQueryItem(name: "ticker", value: "in.(\(tickers.joined(separator: ",")))"),
        ])
        for row in rows { stockIDs[row.ticker.uppercased()] = row.id }
        return rows
    }

    func quote(for ticker: String) async throws -> Quote {
        let ticker = ticker.uppercased()
        if let quote = try await stocks([ticker]).first?.quote { return quote }
        // Tracked but never priced: ask the backend to fetch a price, then read it again.
        try await refreshPrices(ticker)
        guard let quote = try await stocks([ticker]).first?.quote else { throw BackendError.notFound("A price for \(ticker)") }
        return quote
    }

    private func refreshPrices(_ ticker: String) async throws {
        struct Body: Encodable { let ticker: String }
        let _: IgnoredResponse = try await client.invoke("refresh-prices", body: Body(ticker: ticker))
    }

    // MARK: History

    func history(for ticker: String, range: ChartRange) async throws -> [PricePoint] {
        let ticker = ticker.uppercased()
        if stockIDs[ticker] == nil { _ = try await stocks([ticker]) }
        guard let id = stockIDs[ticker] else { return [] }

        let days: Double = switch range {
        case .day: 1
        case .week: 7
        case .month: 31
        case .quarter: 92
        case .year: 366
        }
        let since = Date().addingTimeInterval(-days * 86_400).formatted(.iso8601)

        struct Row: Decodable {
            let price: Double?
            let captured_at: String
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                price = c.flexibleDouble(.price)
                captured_at = try c.decode(String.self, forKey: .captured_at)
            }
            enum CodingKeys: String, CodingKey { case price, captured_at }
        }
        let rows: [Row] = try await client.select("price_history", query: [
            URLQueryItem(name: "select", value: "price,captured_at"),
            URLQueryItem(name: "stock_id", value: "eq.\(id.uuidString)"),
            URLQueryItem(name: "captured_at", value: "gte.\(since)"),
            URLQueryItem(name: "order", value: "captured_at.asc"),
            URLQueryItem(name: "limit", value: "2000"),
        ])
        return rows.compactMap { row in
            guard let price = row.price, let date = BackendDate.parse(row.captured_at) else { return nil }
            return PricePoint(date: date, price: price)
        }
    }

    // MARK: Live

    /// Re-reads quotes every 15 s and yields a tick when a price changes. Every ~5 minutes it also
    /// asks the backend to fetch fresh prices for these tickers.
    func ticks(for tickers: [String]) -> AsyncStream<PriceTick> {
        let tickers = tickers.map { $0.uppercased() }
        let (stream, continuation) = AsyncStream<PriceTick>.makeStream()
        let task = Task { [weak self] in
            var lastUpdate: [String: Date] = [:]
            var poll = 0
            while !Task.isCancelled {
                guard let self else { break }
                if poll % refreshEvery == 0 {
                    for ticker in tickers { try? await refreshPrices(ticker) }
                }
                if let rows = try? await stocks(tickers) {
                    for row in rows {
                        guard let quote = row.quote, lastUpdate[row.ticker] != quote.updatedAt else { continue }
                        lastUpdate[row.ticker] = quote.updatedAt
                        continuation.yield(PriceTick(ticker: row.ticker.uppercased(),
                                                     point: PricePoint(date: quote.updatedAt, price: quote.price)))
                    }
                }
                poll += 1
                try? await Task.sleep(for: pollInterval)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // MARK: Tracking

    func track(_ company: Company) async throws {
        struct Body: Encodable { let ticker: String; let name: String; let domain: String? }
        let _: IgnoredResponse = try await client.invoke(
            "add-stock", body: Body(ticker: company.ticker, name: company.name, domain: company.domain)
        )
        try? await refreshPrices(company.ticker)
    }
}

/// Postgres timestamps: `2026-11-14T20:46:40.275+00:00`, `…40.275123+00`, `…Z`, no fraction.
nonisolated enum BackendDate {
    static func parse(_ raw: String) -> Date? {
        var s = raw.replacingOccurrences(of: " ", with: "T")
        // Normalise "+00" to "+00:00".
        if let range = s.range(of: #"[+-]\d{2}$"#, options: .regularExpression) {
            s.replaceSubrange(range, with: s[range] + ":00")
        }
        // Trim fractions to milliseconds for ISO8601 parsing.
        if let dot = s.firstIndex(of: "."), let end = s[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let digits = s[s.index(after: dot)..<end]
            s.replaceSubrange(s.index(after: dot)..<end, with: String((digits + "000").prefix(3)))
        }
        if let date = try? Date(s, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .colon)) {
            return date
        }
        return try? Date(s, strategy: .iso8601)
    }
}

extension UInt32 {
    /// "#76b900" → 0x76B900
    nonisolated init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self = value
    }
}
