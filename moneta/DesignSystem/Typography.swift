import SwiftUI
import UIKit

/// Quicksand weights bundled with the app (one variable font, named instances 500 / 600 / 700).
enum MonetaWeight: Sendable {
    case medium, semibold, bold

    var postScriptName: String {
        switch self {
        case .medium: "Quicksand-Medium"
        case .semibold: "Quicksand-SemiBold"
        case .bold: "Quicksand-Bold"
        }
    }

    var systemWeight: Font.Weight {
        switch self {
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

enum MonetaFonts {
    /// False when Quicksand failed to register; text then falls back to SF Rounded.
    static let isAvailable: Bool = UIFont(name: MonetaWeight.medium.postScriptName, size: 12) != nil
}

extension Font {
    /// Quicksand at `size`, scaling with Dynamic Type relative to `style`.
    /// Falls back to the rounded system font if Quicksand isn't available.
    static func moneta(size: CGFloat, weight: MonetaWeight = .medium, relativeTo style: Font.TextStyle = .body) -> Font {
        if MonetaFonts.isAvailable {
            return .custom(weight.postScriptName, size: size, relativeTo: style)
        }
        let scaled = UIFontMetrics(forTextStyle: style.uiTextStyle).scaledValue(for: size)
        return .system(size: scaled, weight: weight.systemWeight, design: .rounded)
    }

    // Type scale.
    static let mLargeTitle = moneta(size: 34, weight: .bold, relativeTo: .largeTitle)
    static let mTitle = moneta(size: 28, weight: .bold, relativeTo: .title)
    static let mTitle2 = moneta(size: 22, weight: .bold, relativeTo: .title2)
    static let mTitle3 = moneta(size: 19, weight: .bold, relativeTo: .title3)
    static let mHeadline = moneta(size: 17, weight: .bold, relativeTo: .headline)
    static let mBody = moneta(size: 16, weight: .medium, relativeTo: .body)
    static let mBodyStrong = moneta(size: 16, weight: .semibold, relativeTo: .body)
    static let mCallout = moneta(size: 15, weight: .medium, relativeTo: .callout)
    static let mSubheadline = moneta(size: 14, weight: .semibold, relativeTo: .subheadline)
    static let mFootnote = moneta(size: 13, weight: .medium, relativeTo: .footnote)
    static let mCaption = moneta(size: 12, weight: .semibold, relativeTo: .caption)
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
