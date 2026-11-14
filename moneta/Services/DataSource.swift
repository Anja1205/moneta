import Foundation

/// Where the app's prices and signals come from. Demo is the default: fictional companies on the
/// mock services. Live uses the Moneta backend services in this folder.
enum DataSource: String, CaseIterable, Identifiable, Sendable {
    case demo
    case live

    static let storageKey = "dataSource"

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

    func makeStore() -> MonetaStore {
        switch self {
        case .demo:
            .mock()
        case .live:
            MonetaStore(prices: BackendPriceService(), monitor: BackendWebMonitorService(), agent: BackendSignalAgent())
        }
    }
}
