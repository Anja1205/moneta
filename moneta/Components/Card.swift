import SwiftUI

/// Rounded card: #151922 fill, 26pt corners, 1pt border.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var fill: Color = Palette.card
    var border: Color = Palette.border
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

/// Small uppercase-free section title used above cards.
struct SectionTitle: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.mTitle3)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.mFootnote)
                    .foregroundStyle(Palette.muted)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SectionTitle(text: "Your stocks", trailing: "4 watching")
        Card {
            Text("Card content").font(.mBody).foregroundStyle(Palette.text)
        }
    }
    .padding()
    .background(Palette.background)
}
