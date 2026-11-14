import ActivityKit
import Foundation

/// Live Activity model shared by the app and MonetaWidgetExtension.
/// Must be a member of BOTH targets.
nonisolated struct MonetaAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var ticker: String
        /// "bullish", "bearish" or "neutral".
        var direction: String
        var why: String
        /// 1-5.
        var impact: Int
        var updatedAt: Date

        var directionLabel: String { direction.capitalized }

        var arrowSymbol: String {
            switch direction {
            case "bullish": "arrow.up.right"
            case "bearish": "arrow.down.right"
            default: "arrow.right"
            }
        }

        /// Matches the app theme: bullish #2ECC71, bearish #FF4D5E, neutral #8A8F98.
        var directionRGB: (red: Double, green: Double, blue: Double) {
            switch direction {
            case "bullish": (0x2E / 255.0, 0xCC / 255.0, 0x71 / 255.0)
            case "bearish": (0xFF / 255.0, 0x4D / 255.0, 0x5E / 255.0)
            default: (0x8A / 255.0, 0x8F / 255.0, 0x98 / 255.0)
            }
        }

        static let watching = ContentState(
            ticker: "MONETA",
            direction: "neutral",
            why: "Watching the web for your stocks…",
            impact: 0,
            updatedAt: .now
        )
    }
}
