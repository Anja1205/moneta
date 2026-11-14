import Foundation

// The app talks to these three protocols only. The mock implementations in this folder stand in
// until the real services are wired up; `DataSource` picks which set the app runs on.

/// Market data: company lookup, quotes, price history and live ticks.
protocol PriceService: AnyObject {
    /// Companies matching a name or ticker. Empty query returns popular companies.
    func searchCompanies(_ query: String) async throws -> [Company]
    func quote(for ticker: String) async throws -> Quote
    /// Price points for a range, oldest first. `.day` is the intraday series.
    func history(for ticker: String, range: ChartRange) async throws -> [PricePoint]
    /// Live ticks for the tickers until the stream's consumer stops.
    func ticks(for tickers: [String]) -> AsyncStream<PriceTick>
    /// Makes sure the backend tracks the company and has a price for it. Called when the user adds it.
    func track(_ company: Company) async throws
    /// The watchlist a first launch starts with.
    func defaultWatchlist() async -> [Company]
    /// The signed-in account's watchlist on the backend (filled during onboarding).
    /// `nil` when the service has no accounts.
    func accountWatchlist() async -> [Company]?
}

extension PriceService {
    func accountWatchlist() async -> [Company]? { nil }
}

/// Watches the open web around each company (news, X, careers, pricing, investor pages, changelogs).
///
/// TODO: Back this with Context.dev through your own backend. Don't call Context.dev from the app
/// and don't guess its API here: expose your backend's endpoints, then map their responses to
/// `WebChange`.
protocol WebMonitorService: AnyObject {
    /// Starts (or updates) watching a company's sources.
    func startWatching(_ ticker: String, sources: Set<SignalSource>) async throws
    func stopWatching(_ ticker: String) async throws
    /// Changes already found today for these companies.
    func recentChanges(for tickers: [String]) async throws -> [WebChange]
    /// New changes for every watched company, as they're found.
    func changes() -> AsyncStream<WebChange>
}

/// The agent's judgement on one change.
nonisolated struct SignalAssessment: Hashable, Sendable {
    let impact: Impact
    /// One sentence on why it matters.
    let why: String
}

/// Decides whether a change matters and explains why in one sentence.
///
/// TODO: Call an LLM through your own backend (e.g. a Supabase Edge Function). Never ship model
/// API keys in the app.
protocol SignalAgent: AnyObject {
    /// `nil` when the change doesn't matter.
    func assess(_ change: WebChange, company: Company) async throws -> SignalAssessment?
}
