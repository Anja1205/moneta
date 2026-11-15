import SwiftUI

/// Native TabView with the system Liquid Glass tab bar and a separate Search tab.
struct RootView: View {
    @Environment(MarketStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()

    var body: some View {
        @Bindable var store = store
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Markets", systemImage: "chart.bar.xaxis", value: AppTab.markets) {
                MarketsView()
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
        .errorBanner($store.errorMessage)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.reconnect() } }
        }
        .environment(router)
        .sheet(item: $router.addStock) { target in
            AddStockSheet(preselected: target.company)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $router.showStockSearch) {
            StockSearchView(mode: .watchlist(store))
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: store.alertCount) { _, _ in store.hapticsEnabled }
        #if DEBUG
        .task(id: store.isLoaded) {
            // `-MonetaPosition NVDA:10:150` sets a position, `NVDA:clear` removes it (checks the header).
            if store.isLoaded, let spec = UserDefaults.standard.string(forKey: "MonetaPosition") {
                let parts = spec.split(separator: ":").map(String.init)
                if parts.count >= 2, parts[1] == "clear" {
                    await store.removePosition(parts[0])
                } else if parts.count >= 2 {
                    await store.updatePosition(parts[0], shares: Double(parts[1]), avgCost: parts.count > 2 ? Double(parts[2]) : nil)
                }
            }
            guard store.isLoaded, let route = LaunchRoute.value else { return }
            switch route {
            case "signals": router.tab = .signals
            case "settings": router.tab = .settings
            case "markets": router.tab = .markets
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
        .environment(MarketStore.preview())
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
