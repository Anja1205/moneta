import SwiftUI

/// Shown while the stored session is read: the wordmark over a pulsing gold glow.
struct SplashView: View {
    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            GoldGlow(size: 320, intensity: 0.5, period: 1.4)
            MonetaWordmark(size: 48)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Moneta, loading")
    }
}

#Preview {
    SplashView()
        .preferredColorScheme(.dark)
}
