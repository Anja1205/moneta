import SwiftUI

/// Numbered pin for a signal: high and major = solid amber, medium = amber tint, minor and low = grey.
struct SignalPin: View {
    let number: Int
    let impact: Impact
    var size: CGFloat = 24

    var body: some View {
        Text("\(number)")
            .font(.moneta(size: size * 0.5, weight: .bold, relativeTo: .caption))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .overlay(Circle().strokeBorder(stroke, lineWidth: 1.5))
            .accessibilityLabel("Signal \(number), \(impact.label) impact")
    }

    private var fill: Color {
        switch impact {
        case .major, .high: Palette.amber
        case .medium: Palette.amber.opacity(0.22)
        case .minor, .low: Palette.raised
        }
    }

    private var foreground: Color {
        switch impact {
        case .major, .high: Palette.background
        case .medium: Palette.amber
        case .minor, .low: Palette.secondary
        }
    }

    private var stroke: Color {
        switch impact {
        case .major, .high: Palette.amber
        case .medium: Palette.amber.opacity(0.6)
        case .minor, .low: Palette.border
        }
    }

    /// Chart rule colour for this impact.
    static func color(for impact: Impact) -> Color {
        switch impact {
        case .major, .high: Palette.amber
        case .medium: Palette.amber.opacity(0.55)
        case .minor, .low: Palette.muted
        }
    }
}

#Preview {
    HStack {
        SignalPin(number: 1, impact: .high)
        SignalPin(number: 2, impact: .medium)
        SignalPin(number: 3, impact: .low)
    }
    .padding()
    .background(Palette.background)
}
