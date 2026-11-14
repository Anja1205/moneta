import SwiftUI

/// Moneta colour tokens. Dark mode only.
enum Palette {
    static let background = Color(hex: 0x0B0D12)
    static let card = Color(hex: 0x151922)
    static let raised = Color(hex: 0x1D2230)
    static let border = Color(hex: 0x262C3A)
    static let text = Color(hex: 0xF3F5F9)
    static let secondary = Color(hex: 0xA3ABBC)
    static let muted = Color(hex: 0x8790A3)
    /// Warnings and the accent.
    static let amber = Color(hex: 0xFFB547)
    static let up = Color(hex: 0x5EE3A8)
    static let down = Color(hex: 0xFF7A6B)

    /// Tinted fill for tags and pills: the colour at ~12% opacity.
    static func tint(_ color: Color) -> Color { color.opacity(0.12) }

    /// Green, red or muted for a signed change.
    static func change(_ value: Double) -> Color {
        if abs(value) < 0.0005 { return muted }
        return value > 0 ? up : down
    }
}

/// Corner radii and spacing.
enum Metrics {
    static let cardRadius: CGFloat = 26
    static let iconButton: CGFloat = 44
    static let iconButtonRadius: CGFloat = 16
    static let margin: CGFloat = 20
    static let spacing: CGFloat = 14
}

nonisolated extension Color {
    /// `Color(hex: 0xFFB547)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
