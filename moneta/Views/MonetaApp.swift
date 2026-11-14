import SwiftUI

@main
struct MonetaApp: App {
    /// Live services on the Moneta backend. `MonetaStore.mock()` runs everything on sample data.
    @State private var store = MonetaStore(
        prices: BackendPriceService(),
        monitor: BackendWebMonitorService(),
        agent: BackendSignalAgent()
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .task { await store.start() }
        }
    }
}
