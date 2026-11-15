import SwiftUI

/// Shown while the stored session is read: the app icon with a loading spinner.
struct SplashView: View {
    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 28) {
                Image("MonetaMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                LoadingSpinner()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Moneta, loading")
    }
}

/// Thin gold arc on a faint track, turning steadily. The system spinner when Reduce Motion is on.
struct LoadingSpinner: View {
    var size: CGFloat = 26
    var lineWidth: CGFloat = 2.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            ProgressView().tint(Brand.muted)
        } else {
            TimelineView(.animation) { context in
                let turns = context.date.timeIntervalSinceReferenceDate / 0.9
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(Brand.gold, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
                }
                .frame(width: size, height: size)
            }
        }
    }
}

#Preview {
    SplashView()
        .preferredColorScheme(.dark)
}
