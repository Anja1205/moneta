import SwiftUI

/// Company mark: the logo on a white rounded tile when there's a raster logo, otherwise the
/// company's symbol or initials on a brand-tinted tile.
struct CompanyMark: View {
    let company: Company
    var size: CGFloat = 36

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.3, style: .continuous) }

    /// AsyncImage can't draw SVG, so those fall back to initials.
    private var rasterLogo: URL? {
        guard let url = company.logoURL, !url.pathExtension.lowercased().hasPrefix("svg") else { return nil }
        return url
    }

    var body: some View {
        Group {
            if let rasterLogo {
                AsyncImage(url: rasterLogo, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        ZStack {
                            Color.white
                            image.resizable().scaledToFit().padding(size * 0.14)
                        }
                    } else if case .failure = phase {
                        fallback
                    } else {
                        Palette.raised
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallback: some View {
        let brand = Color(hex: company.brandHex)
        ZStack {
            Palette.tint(brand).opacity(1.4)
            if let symbol = company.symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(brand)
            } else {
                Text(String(company.ticker.filter(\.isLetter).prefix(2)))
                    .font(.moneta(size: size * 0.38, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(brand)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

/// Grid tile for a watched stock: ticker, name, sparkline, price, change and new-signal badge.
struct StockTile: View {
    let company: Company
    let quote: Quote?
    let points: [PricePoint]
    let newCount: Int

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    CompanyMark(company: company, size: 32)
                    Spacer(minLength: 4)
                    if newCount > 0 {
                        CapsuleTag("\(newCount) new", color: Palette.amber)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(company.ticker)
                        .font(.mHeadline)
                        .foregroundStyle(Palette.text)
                    Text(company.name)
                        .font(.mFootnote)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Sparkline(points: points.sparkValues())
                    .frame(height: 38)
                if let quote {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Fmt.price(quote.price, currency: quote.currency))
                            .font(.moneta(size: 18, weight: .bold, relativeTo: .headline))
                            .monospacedDigit()
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText(value: quote.price))
                            .animation(.snappy, value: quote.price)
                        ChangeCapsule(fraction: quote.changeFraction)
                    }
                } else {
                    Text("—").font(.mHeadline).foregroundStyle(Palette.muted)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: newCount)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens \(company.name)")
    }

    private var accessibilityText: String {
        var parts = ["\(company.name), \(company.ticker)"]
        if let quote { parts.append("\(Fmt.price(quote.price, currency: quote.currency)), \(Fmt.percent(quote.changeFraction)) today") }
        if newCount > 0 { parts.append("\(newCount) new signals") }
        return parts.joined(separator: ", ")
    }
}

/// Dashed "Add stock" tile at the end of the grid.
struct AddStockTile: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.amber)
                .frame(width: 48, height: 48)
                .background(Palette.tint(Palette.amber), in: Circle())
            Text("Add stock")
                .font(.mBodyStrong)
                .foregroundStyle(Palette.text)
            Text("Watch another company")
                .font(.mFootnote)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    let company = MockData.companies[0]
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
        StockTile(company: company, quote: Quote(price: 121.82, previousClose: 118.40, updatedAt: .now),
                  points: (0..<40).map { PricePoint(date: .now.addingTimeInterval(Double($0) * 60), price: 118 + Double($0) * 0.1) },
                  newCount: 3)
        AddStockTile()
    }
    .padding()
    .background(Palette.background)
}
