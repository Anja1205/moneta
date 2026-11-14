import SwiftUI

@main struct MyApp: App {
    @State private var store = SignalStore()

    var body: some Scene {
        WindowGroup {
            FeedView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
    }
}
