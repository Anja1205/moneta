import SwiftUI
import UIKit

@main
struct MonetaApp: App {
    @State private var auth = AuthService()

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

        // Sign in / Create account picker.
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(Brand.gold)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.black,
                                          .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.7),
                                          .font: UIFont.systemFont(ofSize: 14, weight: .medium)], for: .normal)
    }

    var body: some Scene {
        WindowGroup {
            // Splash, sign in, onboarding, then the main app (with its store) once onboarded.
            AppRootView()
                .environment(auth)
                .task { await auth.start() }
                .preferredColorScheme(.dark)
        }
    }
}

private extension UIFont {
    func withDesign(_ design: UIFontDescriptor.SystemDesign) -> UIFont {
        fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}
