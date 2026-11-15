import SwiftUI

/// White rounded-square tile with the company logo fitted inside. Falls back to ticker initials
/// on the brand colour (or gold) when there's no logo URL, it's an SVG, or it fails to load.
struct CompanyLogo: View {
    let ticker: String
    var logoURL: URL?
    var brandHex: UInt32?
    var size: CGFloat = 40

    init(ticker: String, logoURL: URL? = nil, brandHex: UInt32? = nil, size: CGFloat = 40) {
        self.ticker = ticker
        self.logoURL = logoURL
        self.brandHex = brandHex
        self.size = size
    }

    init(company: Company, size: CGFloat = 40) {
        self.init(ticker: company.ticker, logoURL: company.logoURL, brandHex: company.brandHex, size: size)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
    }

    private var usableURL: URL? {
        guard let logoURL, logoURL.pathExtension.lowercased() != "svg" else { return nil }
        return logoURL
    }

    var body: some View {
        Group {
            if let url = usableURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(size * 0.14)
                            .frame(width: size, height: size)
                            .background(Color.white)
                    case .failure:
                        initials
                    default:
                        Color.white
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var fillHex: UInt32 { brandHex ?? Brand.goldHex }

    private var initials: some View {
        let letters = String(ticker.filter(\.isLetter).prefix(2)).uppercased()
        return Text(letters.isEmpty ? String(ticker.prefix(2)) : letters)
            .font(.number(size * 0.36, weight: .bold))
            .foregroundStyle(Self.isLight(fillHex) ? Color.black : Color.white)
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size)
            .background(Color(hex: fillHex))
    }

    /// Black text on light brand colours, white on dark.
    private static func isLight(_ hex: UInt32) -> Bool {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.6
    }
}

/// Price and today's change from the `companies` list, right-aligned. Empty when unknown.
struct ListPriceLabel: View {
    let company: Company

    var body: some View {
        if let price = company.listPrice {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.price(price, currency: company.listCurrency ?? "USD"))
                    .font(.number(14))
                    .monospacedDigit()
                    .foregroundStyle(Brand.text)
                if let pct = company.listChangePct {
                    Text(Fmt.percent(pct / 100))
                        .font(.number(12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(abs(pct) < 0.05 ? Brand.muted : pct > 0 ? Brand.bullish : Brand.bearish)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        CompanyLogo(ticker: "NVDA", size: 40)
        CompanyLogo(ticker: "AAPL", brandHex: 0x111111, size: 40)
        CompanyLogo(ticker: "SHOP", logoURL: URL(string: "https://example.com/logo.svg"), brandHex: 0x95BF47, size: 28)
    }
    .padding()
    .background(Brand.background)
}
