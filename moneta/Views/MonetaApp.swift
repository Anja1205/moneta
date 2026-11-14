import SwiftUI

@main
struct MonetaApp: App {
    /// Swap the mocks for real services here (see Services/ServiceProtocols.swift).
    @State private var store = MonetaStore(
        prices: MockPriceService(),
        monitor: MockWebMonitorService(),
        agent: MockSignalAgent()
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
