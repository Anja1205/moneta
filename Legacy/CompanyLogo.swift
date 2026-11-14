import SwiftUI

/// The one company logo used on every screen (the Live Activity has its own).
///
/// A rounded white tile with the logo fitted inside, so dark and light logos both read on the dark UI.
/// While loading it shimmers. With no URL, an `.svg` URL, or a failed load, it shows the ticker
/// initials on a tile filled with the brand colour (or gold).
struct CompanyLogo: View {
    enum Size {
        /// Signal and company rows.
        case row
        /// Watchlist cards.
        case card
        /// Detail headers.
        case header

        var points: CGFloat {
            switch self {
            case .row: 28
            case .card: 40
            case .header: 64
            }
        }
    }

    let ticker: String
    let logoURL: String?
    let brandColor: String?
    var size: Size = .card

    init(ticker: String, logoURL: String?, brandColor: String?, size: Size = .card) {
        self.ticker = ticker
        self.logoURL = logoURL
        self.brandColor = brandColor
        self.size = size
    }

    init(stock: Stock, size: Size = .card) {
        self.init(ticker: stock.ticker, logoURL: stock.logoURL, brandColor: stock.brandColor, size: size)
    }

    private var side: CGFloat { size.points }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: side * 0.22, style: .continuous) }

    /// A loadable raster URL, or nil when we should go straight to initials.
    private var url: URL? {
        guard let raw = logoURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        // AsyncImage can't render SVG.
        if url.path.lowercased().hasSuffix(".svg") { return nil }
        return url
    }

    var body: some View {
        content
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel("\(ticker) logo")
    }

    @ViewBuilder
    private var content: some View {
        if let url {
            if let cached = LogoCache.shared[url] {
                tile(cached)
            } else {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        tile(image)
                            .onAppear { LogoCache.shared[url] = image }
                    case .failure:
                        LogoInitials(ticker: ticker, brandColor: brandColor, side: side)
                    case .empty:
                        LogoShimmer()
                    @unknown default:
                        LogoShimmer()
                    }
                }
            }
        } else {
            LogoInitials(ticker: ticker, brandColor: brandColor, side: side)
        }
    }

    private func tile(_ image: Image) -> some View {
        ZStack {
            Color.white
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(side * 0.14)
        }
    }
}

// MARK: - Cache

/// Small in-memory cache of loaded logos, so rows don't flash a shimmer when they reappear.
@MainActor
final class LogoCache {
    static let shared = LogoCache()

    private var images: [URL: Image] = [:]
    private var order: [URL] = []
    private let limit = 150

    subscript(url: URL) -> Image? {
        get { images[url] }
        set {
            guard let newValue else {
                images[url] = nil
                order.removeAll { $0 == url }
                return
            }
            if images.updateValue(newValue, forKey: url) == nil {
                order.append(url)
                if order.count > limit {
                    images[order.removeFirst()] = nil
                }
            }
        }
    }
}

// MARK: - Pieces

private struct LogoInitials: View {
    let ticker: String
    let brandColor: String?
    let side: CGFloat

    private var fill: Color { brandColor.map(Color.init(hex:)) ?? Theme.gold }

    private var initials: String {
        let letters = String(ticker.filter(\.isLetter).prefix(2)).uppercased()
        return letters.isEmpty ? "?" : letters
    }

    var body: some View {
        ZStack {
            fill
            Text(initials)
                .font(.system(size: side * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(side * 0.1)
        }
    }
}

private struct LogoShimmer: View {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white.opacity(0.10)
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.22), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.8)
                    .offset(x: phase * proxy.size.width * 1.4)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}
