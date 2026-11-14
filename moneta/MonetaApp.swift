import SwiftUI

@main
struct MonetaApp: App {
    @State private var store = SignalStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .task {
                    // Don't hold the feed back while the permission prompt is up.
                    Task { await AlertService.shared.requestPermission() }
                    store.onNewSignal = { AlertService.shared.handle($0) }
                    await store.load()
                    await store.startRealtime()
                }
        }
    }
}

struct RootView: View {
    @Environment(SignalStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var didBecomeActive = false

    var body: some View {
        TabView {
            WatchlistView()
                .tabItem { Label("Watchlist", systemImage: "eye") }
            FeedView()
                .tabItem { Label("Live Feed", systemImage: "dot.radiowaves.left.and.right") }
            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // The first activation is covered by the app's .task.
                guard didBecomeActive else { didBecomeActive = true; return }
                Task {
                    await store.load()
                    await store.startRealtime()
                }
            case .background:
                Task { await store.stopRealtime() }
            default:
                break
            }
        }
    }
}
