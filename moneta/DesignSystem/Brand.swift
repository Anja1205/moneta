import SwiftUI

/// Design tokens for the auth, onboarding, search and account screens. Dark mode only.
nonisolated enum Brand {
    static let goldHex: UInt32 = 0xE8B44A

    static let background = Color(hex: 0x0B0D10)
    static let card = Color(hex: 0x16191E)
    static let border = Color.white.opacity(0.06)
    static let gold = Color(hex: goldHex)
    static let bullish = Color(hex: 0x2ECC71)
    static let bearish = Color(hex: 0xFF4D5E)
    static let text = Color.white
    static let muted = Color.white.opacity(0.55)

    static let cardRadius: CGFloat = 20
    static let margin: CGFloat = 16
    static let spacing: CGFloat = 12
}

extension Font {
    /// The "Moneta" wordmark: serif, semibold.
    static func wordmark(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    /// Numbers: SF Pro Rounded.
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Gold serif "Moneta".
struct MonetaWordmark: View {
    var size: CGFloat = 40

    var body: some View {
        Text("Moneta")
            .font(.wordmark(size))
            .foregroundStyle(Brand.gold)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Card

extension View {
    /// #16191E fill, 20pt corners, 1pt white 6% border.
    func brandCard(padding: CGFloat = 0) -> some View {
        self
            .padding(padding)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                    .strokeBorder(Brand.border, lineWidth: 1)
            )
    }
}

// MARK: - Primary button

/// Full-width gold button. Gray when disabled, spinner while loading.
struct PrimaryButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(.black)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.black : Color.white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                isEnabled ? Brand.gold : Color(white: 0.22),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .allowsHitTesting(!isLoading)
        .animation(.easeOut(duration: 0.2), value: isEnabled)
        .animation(.easeOut(duration: 0.2), value: isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "Loading" : "")
    }
}

/// Slight scale-down while pressed.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Glow

/// Soft gold radial glow that slowly pulses. Still when Reduce Motion is on.
struct GoldGlow: View {
    var size: CGFloat = 300
    var intensity: Double = 0.45
    /// Seconds for one swell.
    var period: Double = 2

    @State private var swell = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Brand.gold.opacity(intensity), Brand.gold.opacity(intensity * 0.25), .clear],
                    center: .center, startRadius: 0, endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .scaleEffect(swell ? 1.08 : 0.9)
            .opacity(swell ? 1 : 0.6)
            .blur(radius: 24)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) { swell = true }
            }
    }
}

// MARK: - Shake

/// Horizontal shake; bump `travel` by 1 inside `withAnimation` to shake once.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(travel * .pi * 4), y: 0))
    }
}

// MARK: - Shimmer

/// A light band that sweeps across loading placeholders.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.08), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.6)
                    .offset(x: phase * proxy.size.width * 1.3)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.3 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

/// Placeholder row while companies load.
struct ShimmerRow: View {
    var logoSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: logoSize * 0.22, style: .continuous)
                .frame(width: logoSize, height: logoSize)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().frame(width: 140, height: 12)
                Capsule().frame(width: 60, height: 10)
            }
            Spacer()
            Circle().frame(width: 32, height: 32)
        }
        .foregroundStyle(Color.white.opacity(0.07))
        .padding(12)
        .brandCard()
        .shimmer()
        .accessibilityHidden(true)
    }
}

// MARK: - Add / select toggle

/// Circular "+" that becomes a gold filled checkmark. Shows a spinner while `isBusy`.
struct AddToggleIcon: View {
    let isOn: Bool
    var isBusy = false
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            if isBusy {
                ProgressView()
                    .tint(Brand.gold)
                    .transition(.opacity)
            } else if isOn {
                Circle().fill(Brand.gold)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.black)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
                Image(systemName: "plus")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Brand.text)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isOn ? 1 : 0.94)
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: isOn)
        .animation(.easeOut(duration: 0.15), value: isBusy)
    }
}

/// Muted card-style search field.
struct BrandSearchField: View {
    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Brand.muted)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Brand.muted))
                .focused(focus)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(Brand.text)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Brand.muted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 48)
        .brandCard()
    }
}
