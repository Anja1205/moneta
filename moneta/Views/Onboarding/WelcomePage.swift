import SwiftUI

/// Onboarding page 1: what Moneta does.
struct WelcomePage: View {
    let onContinue: () -> Void

    private let features: [(icon: String, text: String)] = [
        ("newspaper", "Breaking news, as it happens"),
        ("sparkles", "AI explains why it matters"),
        ("bell.badge", "Alerts on your lock screen"),
    ]

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        MonetaWordmark(size: 44)
                        Text("Moneta watches the live web around your stocks and warns you before the market moves.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Brand.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: Brand.spacing) {
                        ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                            FeatureRow(icon: feature.icon, text: feature.text)
                                .opacity(index < shown ? 1 : 0)
                                .offset(y: index < shown ? 0 : 14)
                        }
                    }
                }
                .padding(.horizontal, Brand.margin)
                .padding(.top, 40)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            PrimaryButton("Get started", action: onContinue)
                .padding(.horizontal, Brand.margin)
                .padding(.bottom, 8)
        }
        .task {
            if reduceMotion {
                shown = features.count
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            for index in features.indices {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { shown = index + 1 }
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Brand.gold)
                .frame(width: 44, height: 44)
                .background(Brand.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(Brand.text)
            Spacer(minLength: 0)
        }
        .padding(14)
        .brandCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomePage {}
        .background(Brand.background)
        .preferredColorScheme(.dark)
}
