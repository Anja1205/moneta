import Foundation
import Supabase

/// Calls that don't belong to a long-lived store.
enum MonetaAPI {
    /// The Top 20, ordered by rank.
    static func featuredCompanies() async throws -> [Company] {
        try await supabase
            .from("companies")
            .select("ticker,name,domain,rank,featured,logo_url,brand_color")
            .eq("featured", value: true)
            .order("rank")
            .execute()
            .value
    }

    /// `companies.logo_url` / `brand_color` keyed by uppercase ticker, for search hits that lack them.
    /// Returns an empty map on failure: logos are decoration, never a reason to fail a search.
    static func companyBranding(tickers: [String]) async -> [String: CompanyBranding] {
        let unique = Array(Set(tickers.map { $0.uppercased() }))
        guard !unique.isEmpty else { return [:] }
        do {
            let rows: [CompanyBranding] = try await supabase
                .from("companies")
                .select("ticker,logo_url,brand_color")
                .in("ticker", values: unique)
                .execute()
                .value
            return Dictionary(rows.map { ($0.ticker.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            return [:]
        }
    }

    static func searchCompanies(query: String) async throws -> [CompanySearchResult] {
        struct Body: Encodable { let query: String }
        let response: CompanySearchResponse = try await supabase.functions.invoke(
            "search-companies",
            options: FunctionInvokeOptions(body: Body(query: query))
        )
        return response.results
    }

    /// Adds the stock and puts it on the signed-in user's watchlist.
    static func addStock(ticker: String, name: String? = nil, domain: String? = nil) async throws -> AddStockResponse {
        try await supabase.functions.invoke(
            "add-stock",
            options: FunctionInvokeOptions(body: AddStockRequest(ticker: ticker, name: name, domain: domain))
        )
    }
}
