import SwiftUI

/// Capsule tag with a tinted fill: `CapsuleTag("High signal", color: Palette.amber)`.
struct CapsuleTag: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = Palette.secondary
    /// Solid fill with dark text instead of a tint.
    var solid = false

    init(_ text: String, systemImage: String? = nil, color: Color = Palette.secondary, solid: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
        self.solid = solid
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.mCaption)
        .foregroundStyle(solid ? Palette.background : color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(solid ? color : Palette.tint(color), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// "+2.8%" capsule in green or red with an arrow.
struct ChangeCapsule: View {
    let fraction: Double
    var large = false

    var body: some View {
        let color = Palette.change(fraction)
        HStack(spacing: 3) {
            Image(systemName: abs(fraction) < 0.0005 ? "minus" : fraction > 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: large ? 12 : 10, weight: .heavy))
            Text(Fmt.percent(fraction))
                .monospacedDigit()
                .contentTransition(.numericText(value: fraction))
        }
        .font(large ? .mSubheadline : .mCaption)
        .foregroundStyle(color)
        .padding(.horizontal, large ? 12 : 8)
        .padding(.vertical, large ? 6 : 4)
        .background(Palette.tint(color), in: Capsule())
        .fixedSize()
        .animation(.snappy, value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(abs(fraction) < 0.0005 ? "Unchanged" : "\(fraction > 0 ? "Up" : "Down") \(Fmt.percent(abs(fraction)))")
    }
}

/// Impact capsule: high and major = solid amber, medium = amber tint, minor and low = grey.
struct ImpactTag: View {
    let impact: Impact

    var body: some View {
        switch impact {
        case .major, .high: CapsuleTag(impact.label, systemImage: "exclamationmark.triangle.fill", color: Palette.amber, solid: true)
        case .medium: CapsuleTag(impact.label, systemImage: "eye", color: Palette.amber)
        case .minor, .low: CapsuleTag(impact.label, color: Palette.muted)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        CapsuleTag("Investor page", systemImage: "building.columns")
        ChangeCapsule(fraction: 0.028)
        ChangeCapsule(fraction: -0.014, large: true)
        ForEach(Impact.allCases, id: \.self) { ImpactTag(impact: $0) }
    }
    .padding()
    .background(Palette.background)
}
