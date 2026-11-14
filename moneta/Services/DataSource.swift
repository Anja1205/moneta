import Foundation

/// Where the app's prices and signals come from. Live (the Moneta backend) is the default, so the
/// watchlist is the one the user picked in onboarding. Demo runs fictional companies on the mock
/// services and ignores the account's watchlist.
enum DataSource: String, CaseIterable, Identifiable, Sendable {
    case demo
    case live

    static let storageKey = "dataSource"
    static let `default`: DataSource = .live

    var id: Self { self }

    var label: String {
        switch self {
        case .demo: "Demo data"
        case .live: "Moneta backend"
        }
    }

    var explanation: String {
        switch self {
        case .demo:
            "Fictional companies on a simulated market. Prices tick every few seconds and new signals arrive now and then."
        case .live:
            "Prices, company search and signals come from the Moneta backend, which watches the web through Context.dev and rates each change with an AI agent."
        }
    }

    /// A store for one signed-in user; their saved watchlist is kept apart from other users'.
    func makeStore(userID: UUID? = nil) -> MonetaStore {
        switch self {
        case .demo:
            MonetaStore(prices: MockPriceService(), monitor: MockWebMonitorService(), agent: MockSignalAgent(), userID: userID)
        case .live:
            MonetaStore(prices: BackendPriceService(), monitor: BackendWebMonitorService(), agent: BackendSignalAgent(),
                        userID: userID)
        }
    }
}
