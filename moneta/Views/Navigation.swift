import SwiftUI

enum AppTab: Hashable {
    case home, markets, signals, settings, search
}

/// Pushed screens.
enum Route: Hashable {
    case stock(String)
    case signal(UUID)
}

/// What the Add stock sheet opens with.
struct AddStockTarget: Identifiable {
    let id = UUID()
    var company: Company?
}

/// Cross-tab navigation: the selected tab and the Add stock sheet.
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var addStock: AddStockTarget?
    /// The stock search sheet (watchlist mode), opened from Home's "+".
    var showStockSearch = false
    #if DEBUG
    /// Launch-argument route for the Home stack to push (see LaunchRoute).
    var pending: String?
    #endif
}

extension View {
    /// Destinations shared by every tab's NavigationStack.
    func monetaDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .stock(let ticker): StockDetailView(ticker: ticker)
            case .signal(let id): SignalDetailView(signalID: id)
            }
        }
    }

    /// Screen background that runs under the glass bars.
    func monetaScreen() -> some View {
        background(Palette.background.ignoresSafeArea())
    }
}
