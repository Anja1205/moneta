import SwiftUI

struct StockLogo: View {
    let ticker: String
    let logoURL: String?
    let brandColor: String?
    var size: CGFloat = 36

    private var tint: Color { brandColor.map(Color.init(hex:)) ?? Theme.gold }

    /// AsyncImage cannot draw SVG, so only raster logos are attempted.
    private var rasterURL: URL? {
        guard let logoURL, let url = URL(string: logoURL),
              !url.pathExtension.lowercased().hasPrefix("svg") else { return nil }
        return url
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(tint.opacity(0.16))
            if let rasterURL {
                AsyncImage(url: rasterURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.18)
                    } else {
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private var monogram: some View {
        Text(String(ticker.prefix(ticker.count > 3 ? 1 : 2)))
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .minimumScaleFactor(0.5)
    }
}

struct DirectionBadge: View {
    let direction: Direction

    var body: some View {
        let color = Theme.color(for: direction)
        Label(direction.label, systemImage: direction.symbol)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct ImpactMeter: View {
    let impact: Int
    let direction: Direction
    var barWidth: CGFloat = 5

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(1...5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(level <= impact ? Theme.color(for: direction) : Color.white.opacity(0.1))
                    .frame(width: barWidth, height: 6 + CGFloat(level) * 2.4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Impact \(impact) of 5")
    }
}

struct LivePulse: View {
    let isLive: Bool
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if isLive {
                    Circle()
                        .fill(Theme.bullish.opacity(0.35))
                        .frame(width: 14, height: 14)
                        .scaleEffect(pulsing ? 1.4 : 0.6)
                        .opacity(pulsing ? 0 : 1)
                }
                Circle()
                    .fill(isLive ? Theme.bullish : Theme.neutral)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 14, height: 14)
            Text(isLive ? "LIVE" : "OFFLINE")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(isLive ? Theme.bullish : Theme.neutral)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    var leading: AnyView?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let leading { leading }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Theme.background : Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(isSelected ? Theme.background.opacity(0.7) : Theme.textTertiary)
                    }
                }
            }
            .padding(.leading, leading == nil ? 14 : 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(isSelected ? Theme.gold : Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
