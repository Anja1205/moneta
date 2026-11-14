import SwiftUI

/// Native TabView with the system Liquid Glass tab bar and a separate Search tab.
struct RootView: View {
    @Environment(MonetaStore.self) private var store
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Signals", systemImage: "waveform.path.ecg", value: AppTab.signals) {
                SignalsView()
            }
            .badge(unseenAlerts)
            Tab("Settings", systemImage: "slider.horizontal.3", value: AppTab.settings) {
                SettingsView()
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .tint(Palette.amber)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(router)
        .sheet(item: $router.addStock) { target in
            AddStockSheet(preselected: target.company)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: store.alertCount) { _, _ in store.hapticsEnabled }
        #if DEBUG
        .task(id: store.isLoaded) {
            guard store.isLoaded, let route = LaunchRoute.value else { return }
            switch route {
            case "signals": router.tab = .signals
            case "settings": router.tab = .settings
            case "search": router.tab = .search
            case "add": router.addStock = AddStockTarget(company: nil)
            case "addORLA": router.addStock = AddStockTarget(company: store.company("ORLA"))
            default: router.pending = route
            }
        }
        #endif
    }

    private var unseenAlerts: Int {
        store.watched.reduce(0) { $0 + store.newCount(for: $1.ticker) }
    }
}

#Preview {
    RootView()
        .environment(MonetaStore.preview())
        .preferredColorScheme(.dark)
}
