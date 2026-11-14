import Foundation
import Supabase

/// The app's one Supabase client (auth, tables, Edge Functions). The session is kept in the
/// Keychain and refreshed automatically.
nonisolated let supabase = SupabaseClient(
    supabaseURL: BackendConfig.url,
    supabaseKey: BackendConfig.publishableKey,
    options: SupabaseClientOptions(
        auth: .init(emitLocalSessionAsInitialSession: true)
    )
)

/// One-off backend calls used by onboarding and the stock search sheet.
nonisolated enum MonetaAPI {
    /// The Top 20 (`companies.featured = true`), ordered by rank.
    static func featuredCompanies() async throws -> [Company] {
        let rows: [CompanyRow] = try await supabase
            .from("companies")
            .select("ticker,name,domain,rank,logo_url,brand_color")
            .eq("featured", value: true)
            .order("rank")
            .execute()
            .value
        return rows.map(\.company)
    }

    /// `search-companies`: catalog hits plus live Context.dev results, with logos from `companies`.
    static func searchCompanies(_ query: String) async throws -> [Company] {
        struct Body: Encodable, Sendable { let query: String }
        struct Response: Decodable, Sendable {
            struct Hit: Decodable, Sendable {
                let ticker: String
                let name: String
                let domain: String?
                let source: String?
            }
            let results: [Hit]
        }
        let response: Response = try await supabase.functions.invoke(
            "search-companies",
            options: FunctionInvokeOptions(body: Body(query: query))
        )
        var seen = Set<String>()
        let hits = response.results.filter { seen.insert($0.ticker.uppercased()).inserted }
        let branding = await branding(for: hits.map { $0.ticker.uppercased() })
        return hits.map { hit in
            let ticker = hit.ticker.uppercased()
            var company = Company(ticker: ticker, name: hit.name, brandHex: Brand.goldHex, domain: hit.domain)
            company.source = hit.source
            if let brand = branding[ticker] {
                company.logoURL = brand.logoURL
                company.brandHex = brand.brandHex ?? Brand.goldHex
            }
            return company
        }
    }

    /// `add-stock`: adds the company to the signed-in user's watchlist.
    static func addStock(_ company: Company) async throws {
        struct Body: Encodable, Sendable {
            let ticker: String
            let name: String?
            let domain: String?
        }
        try await supabase.functions.invoke(
            "add-stock",
            options: FunctionInvokeOptions(body: Body(ticker: company.ticker, name: company.name, domain: company.domain))
        )
    }

    /// Logos and brand colours keyed by ticker. Empty on failure: logos never fail a search.
    private static func branding(for tickers: [String]) async -> [String: CompanyRow] {
        guard !tickers.isEmpty else { return [:] }
        let rows: [CompanyRow]? = try? await supabase
            .from("companies")
            .select("ticker,name,domain,rank,logo_url,brand_color")
            .in("ticker", values: tickers)
            .execute()
            .value
        return Dictionary((rows ?? []).map { ($0.ticker.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    struct CompanyRow: Decodable, Sendable {
        let ticker: String
        let name: String
        let domain: String?
        let rank: Int?
        let logo_url: String?
        let brand_color: String?

        var logoURL: URL? { logo_url.flatMap(URL.init(string:)) }
        var brandHex: UInt32? { brand_color.flatMap(UInt32.init(hexString:)) }

        var company: Company {
            var company = Company(ticker: ticker.uppercased(), name: name, brandHex: brandHex ?? Brand.goldHex,
                                  logoURL: logoURL, domain: domain)
            company.rank = rank
            company.source = "catalog"
            return company
        }
    }
}
