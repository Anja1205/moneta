import SwiftUI

extension Palette {
    /// Green for bullish, red for bearish, grey for neutral.
    static func direction(_ direction: Direction) -> Color {
        switch direction {
        case .bullish: up
        case .bearish: down
        case .neutral: muted
        }
    }
}

/// Five dots filled up to the impact, in the direction colour, with an optional "High · 4/5".
struct ImpactMeter: View {
    let impact: Impact
    let direction: Direction
    var showsLabel = true
    var dotSize: CGFloat = 6

    var body: some View {
        let color = Palette.direction(direction)
        HStack(spacing: 6) {
            HStack(spacing: dotSize * 0.6) {
                ForEach(1...5, id: \.self) { index in
                    Circle()
                        .fill(index <= impact.rawValue ? color : Palette.border)
                        .frame(width: dotSize, height: dotSize)
                }
            }
            if showsLabel {
                Text(impact.scoreLabel)
                    .font(.mCaption)
                    .monospacedDigit()
                    .foregroundStyle(impact.isImportant ? Palette.text : Palette.secondary)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(impact.label) impact, \(impact.rawValue) of 5")
    }
}

/// Arrow badge: "↗ Bullish" in green, "↘ Bearish" in red, "→ Neutral" in grey.
struct DirectionBadge: View {
    let direction: Direction
    var large = false

    var body: some View {
        let color = Palette.direction(direction)
        HStack(spacing: large ? 6 : 4) {
            Image(systemName: direction.symbol)
                .font(.system(size: large ? 15 : 10, weight: .heavy))
            Text(direction.label)
        }
        .font(large ? .mHeadline : .mCaption)
        .foregroundStyle(color)
        .padding(.horizontal, large ? 14 : 8)
        .padding(.vertical, large ? 8 : 4)
        .background(Palette.tint(color), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(direction.label)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        ForEach(Impact.allCases, id: \.self) { impact in
            HStack {
                ImpactMeter(impact: impact, direction: impact == .low ? .neutral : impact.rawValue.isMultiple(of: 2) ? .bearish : .bullish)
                Spacer()
                DirectionBadge(direction: impact.rawValue.isMultiple(of: 2) ? .bearish : .bullish)
            }
        }
        DirectionBadge(direction: .bullish, large: true)
    }
    .padding()
    .background(Palette.background)
}
