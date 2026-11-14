import SwiftUI

/// Colours along the 0–100 sentiment scale: red (bearish) → grey (neutral) → green (bullish).
enum SentimentScale {
    static let colors: [Color] = [Theme.bearish, Theme.neutral, Theme.bullish]

    static func color(for sentiment: StockSentiment) -> Color {
        Theme.color(for: sentiment.direction)
    }
}

/// Semicircle gauge 0–100 with a needle that animates to the score, the score in the middle,
/// its label, and a one-line summary of recent signals.
struct SentimentGauge: View {
    let sentiment: StockSentiment

    /// Starts at the neutral midpoint and springs to the score, so the needle visibly settles.
    @State private var shown: Double = 50
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 40

    private var target: Double { Double(min(max(sentiment.score, 0), 100)) }

    var body: some View {
        VStack(spacing: 14) {
            dial
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity)

            Text(sentiment.summary)
                .font(Theme.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .onAppear { settle() }
        .onChange(of: sentiment.score) { _, _ in settle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Web sentiment \(sentiment.score) out of 100, \(sentiment.label)")
        .accessibilityValue(sentiment.summary)
    }

    private var dial: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let line = max(width * 0.06, 10)
            let radius = (width - line) / 2
            let pivot = CGPoint(x: width / 2, y: radius + line / 2)

            ZStack {
                // Track: top half of a circle, red on the left through grey to green on the right.
                Circle()
                    .trim(from: 0.5, to: 1)
                    .stroke(
                        AngularGradient(
                            colors: SentimentScale.colors,
                            center: .center,
                            startAngle: .degrees(180),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: line, lineCap: .round)
                    )
                    .frame(width: radius * 2, height: radius * 2)
                    .position(pivot)
                    .opacity(0.9)

                // Ticks at the band edges (25 / 45 / 55 / 75).
                ForEach([25.0, 45, 55, 75], id: \.self) { value in
                    Capsule()
                        .fill(Theme.background.opacity(0.9))
                        .frame(width: 2, height: line + 2)
                        .offset(y: -radius)
                        .rotationEffect(angle(for: value))
                        .position(pivot)
                }

                // Needle, pointing from the pivot towards the score.
                Capsule()
                    .fill(Theme.textPrimary)
                    .frame(width: 4, height: radius * 0.72)
                    .offset(y: -radius * 0.36)
                    .rotationEffect(angle(for: shown))
                    .position(pivot)
                    .shadow(color: .black.opacity(0.5), radius: 3)

                Circle()
                    .fill(Theme.textPrimary)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 3))
                    .position(pivot)

                // Score and label, centred under the pivot.
                VStack(spacing: 2) {
                    Text("\(sentiment.score)")
                        .font(.system(size: scoreSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: target))
                    Text(sentiment.label)
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(SentimentScale.color(for: sentiment))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .position(x: pivot.x, y: pivot.y + 14 + scoreSize * 0.75)

                // Scale ends.
                Text("0")
                    .position(x: line / 2, y: pivot.y + line + 4)
                Text("100")
                    .position(x: width - line / 2, y: pivot.y + line + 4)
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.textTertiary)
        }
        // Semicircle plus room for the score and label under the pivot.
        .aspectRatio(1 / 0.82, contentMode: .fit)
        .padding(.bottom, scoreSize * 0.6)
    }

    /// 0 → pointing left (-90°), 50 → up, 100 → right (+90°).
    private func angle(for value: Double) -> Angle {
        .degrees(-90 + value * 1.8)
    }

    private func settle() {
        if reduceMotion {
            shown = target
        } else {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.62).delay(0.15)) {
                shown = target
            }
        }
    }
}

/// Thin capsule filled to the score in the matching colour, for watchlist cards.
struct SentimentMiniBar: View {
    let sentiment: StockSentiment

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(SentimentScale.color(for: sentiment))
                        .frame(width: max(proxy.size.width * CGFloat(min(max(sentiment.score, 0), 100)) / 100, 4))
                }
            }
            .frame(height: 4)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: sentiment.score)

            Text("\(sentiment.score)")
                .font(Theme.number(.caption, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(SentimentScale.color(for: sentiment))
                .contentTransition(.numericText(value: Double(sentiment.score)))
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Web sentiment \(sentiment.score) out of 100, \(sentiment.label)")
    }
}
