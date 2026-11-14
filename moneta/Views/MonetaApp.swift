import SwiftUI
import UIKit

@main
struct MonetaApp: App {
    /// Demo data by default; Settings switches to the Moneta backend.
    @AppStorage(DataSource.storageKey) private var source: DataSource = .demo

    init() {
        // Navigation titles in Quicksand too (system rounded if it didn't load).
        func font(_ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont(name: MonetaWeight.bold.postScriptName, size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .bold).withDesign(.rounded)
            return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
        }
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: font(34, .largeTitle), .foregroundColor: UIColor(Palette.text)]
        appearance.titleTextAttributes = [.font: font(17, .headline), .foregroundColor: UIColor(Palette.text)]
    }

    var body: some Scene {
        WindowGroup {
            StoreHost(source: source)
                .id(source)
                .preferredColorScheme(.dark)
        }
    }
}

/// Owns the store for one data source. A new source gets a new host, so a fresh store.
private struct StoreHost: View {
    @State private var store: MonetaStore

    init(source: DataSource) {
        _store = State(initialValue: source.makeStore())
    }

    var body: some View {
        RootView()
            .environment(store)
            .task { await store.start() }
            .onDisappear { store.stop() }
    }
}

private extension UIFont {
    func withDesign(_ design: UIFontDescriptor.SystemDesign) -> UIFont {
        fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}
