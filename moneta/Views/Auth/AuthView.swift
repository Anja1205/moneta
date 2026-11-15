import SwiftUI

/// Sign in or create an account with email and password.
///
/// A hero that shows what Moneta does (a price line with a signal spotted before the move),
/// then a raised panel with the mode switch, floating-label fields and the primary button.
struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case create = "Create account"
        var id: Self { self }

        var title: String {
            switch self {
            case .signIn: "Welcome back"
            case .create: "Create your account"
            }
        }

        var subtitle: String {
            switch self {
            case .signIn: "Sign in to see what the web is saying about your stocks."
            case .create: "Pick the stocks you own next. It takes under a minute."
            }
        }
    }

    private enum Field: Hashable {
        case name, email, password
    }

    @Environment(AuthService.self) private var auth
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var shakes: CGFloat = 0
    @FocusState private var focus: Field?

    private var isEmailValid: Bool {
        email.trimmingCharacters(in: .whitespaces).wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]{2,}/) != nil
    }

    private var isPasswordValid: Bool { password.count >= 6 }

    private var isValid: Bool {
        isEmailValid && isPasswordValid
            && (mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// The hero shrinks to the brand row while typing so the button stays above the keyboard.
    private var isTyping: Bool { focus != nil }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 0) {
                        AuthHero(compact: isTyping)
                            .frame(height: isTyping ? 96 : max(250, proxy.size.height * (mode == .create ? 0.28 : 0.36)))
                        panel
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: focus) { _, field in
                    guard field != nil else { return }
                    withAnimation(.easeOut(duration: 0.25)) { scroller.scrollTo("submit", anchor: .bottom) }
                }
            }
        }
        .background {
            // The glow sits behind the whole screen so it runs up under the status bar.
            ZStack(alignment: .top) {
                Brand.background
                RadialGradient(colors: [Brand.gold.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 360)
                    .frame(height: 420)
                // Panel colour under the home indicator, so the panel reads as running off the bottom.
                VStack {
                    Spacer()
                    Brand.card.frame(height: 160)
                }
            }
            .ignoresSafeArea()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: isTyping)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: mode)
        .animation(.easeOut(duration: 0.2), value: auth.errorMessage)
        .onChange(of: mode) { _, _ in auth.errorMessage = nil }
        #if DEBUG
        .onAppear { if LaunchRoute.value == "authCreate" { mode = .create } }
        #endif
    }

    // MARK: Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModeSwitch(mode: $mode)

            VStack(alignment: .leading, spacing: 6) {
                Text(mode.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Brand.text)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                Text(mode.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .animation(.easeInOut(duration: 0.2), value: mode)

            fields

            VStack(spacing: 12) {
                PrimaryButton(mode.rawValue, isLoading: auth.isLoading, action: submit)
                    .disabled(!isValid)
                    .id("submit")

                if let error = auth.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Brand.bearish)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .modifier(ShakeEffect(travel: shakes))
                        .transition(.opacity)
                }
            }

            switchPrompt
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Circle().fill(Brand.bullish).frame(width: 6, height: 6)
                Text("Live web data by Context.dev")
            }
            .font(.caption)
            .foregroundStyle(Brand.muted)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(Brand.card)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center),
                            lineWidth: 1
                        )
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var fields: some View {
        VStack(spacing: 12) {
            if mode == .create {
                AuthField(label: "Name", icon: "person", isFocused: focus == .name, isEmpty: name.isEmpty) {
                    TextField("", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .name)
                        .onSubmit { focus = .email }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            AuthField(label: "Email", icon: "envelope", isFocused: focus == .email, isEmpty: email.isEmpty) {
                TextField("", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            } accessory: {
                if isEmailValid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Brand.bullish)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Valid email")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                AuthField(label: "Password", icon: "lock", isFocused: focus == .password, isEmpty: password.isEmpty) {
                    Group {
                        if showPassword {
                            TextField("", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("", text: $password)
                        }
                    }
                    .textContentType(mode == .create ? .newPassword : .password)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit(submit)
                } accessory: {
                    Button {
                        showPassword.toggle()
                        if focus == .password {
                            // Swapping fields drops focus; put it back.
                            Task { focus = .password }
                        }
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(Brand.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }

                if mode == .create {
                    Label("At least 6 characters", systemImage: isPasswordValid ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isPasswordValid ? Brand.bullish : Brand.muted)
                        .padding(.leading, 6)
                        .contentTransition(.symbolEffect(.replace))
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: isPasswordValid)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mode)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEmailValid)
    }

    private var switchPrompt: some View {
        HStack(spacing: 4) {
            Text(mode == .signIn ? "New to Moneta?" : "Already have an account?")
                .foregroundStyle(Brand.muted)
            Button(mode == .signIn ? "Create account" : "Sign in") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    mode = mode == .signIn ? .create : .signIn
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(Brand.gold)
        }
        .font(.subheadline)
        .frame(minHeight: 44)
    }

    // MARK: Submit

    private func submit() {
        guard isValid, !auth.isLoading else { return }
        focus = nil
        Task {
            if mode == .create {
                await auth.signUp(name: name, email: email, password: password)
            } else {
                await auth.signIn(email: email, password: password)
            }
            if auth.errorMessage != nil {
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            }
        }
    }
}

// MARK: - Mode switch

/// Two-option pill; a gold capsule slides to the selected side.
private struct ModeSwitch: View {
    @Binding var mode: AuthView.Mode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AuthView.Mode.allCases) { option in
                let isSelected = option == mode
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { mode = option }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.black : Brand.muted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Brand.gold)
                                    .matchedGeometryEffect(id: "mode", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.35), in: Capsule())
        .overlay(Capsule().strokeBorder(Brand.border, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: mode)
    }
}

// MARK: - Field

/// Text field with an icon, a label that floats above the text once there is any (or it's
/// focused), a gold border while focused and an optional trailing accessory.
private struct AuthField<Input: View, Accessory: View>: View {
    let label: String
    let icon: String
    let isFocused: Bool
    let isEmpty: Bool
    @ViewBuilder var input: Input
    @ViewBuilder var accessory: Accessory

    init(label: String, icon: String, isFocused: Bool, isEmpty: Bool,
         @ViewBuilder input: () -> Input, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.label = label
        self.icon = icon
        self.isFocused = isFocused
        self.isEmpty = isEmpty
        self.input = input()
        self.accessory = accessory()
    }

    private var floats: Bool { isFocused || !isEmpty }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isFocused ? Brand.gold : Brand.muted)
                .frame(width: 20)
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                Text(label)
                    .font(floats ? .caption.weight(.medium) : .body)
                    .foregroundStyle(isFocused ? Brand.gold : Brand.muted)
                    .offset(y: floats ? -11 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                input
                    .font(.body)
                    .foregroundStyle(Brand.text)
                    .tint(Brand.gold)
                    .offset(y: floats ? 8 : 0)
                    .accessibilityLabel(label)
            }

            accessory
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 56)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isFocused ? Brand.gold.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: floats)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Hero

/// Brand row, tagline and a price line where a signal is spotted before the move.
private struct AuthHero: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("MonetaMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
                Text("Moneta")
                    .font(.wordmark(28))
                    .foregroundStyle(Brand.gold)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, compact ? 24 : 20)

            if !compact {
                Text("The web knows first. Now so do you.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                    .padding(.top, 8)
                    .transition(.opacity)

                SignalChart()
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A rising price line that draws itself, a pulsing marker where Moneta spotted the change,
/// and the alert that came with it.
private struct SignalChart: View {
    /// y from the top (0) to the bottom (1); the line breaks upward after the signal.
    private static let points: [CGFloat] = [
        0.70, 0.66, 0.72, 0.68, 0.74, 0.69, 0.71, 0.66, 0.70, 0.67,
        0.62, 0.50, 0.44, 0.38, 0.42, 0.33, 0.28, 0.31, 0.22, 0.18,
    ]
    private static let signalIndex = 9

    @State private var drawn: CGFloat = 0
    @State private var showAlert = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let marker = Self.point(Self.signalIndex, in: size)

            ZStack(alignment: .topLeading) {
                // Faint horizontal guides.
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
                        Spacer(minLength: 0)
                    }
                }

                PriceLine(points: Self.points, closed: true)
                    .fill(LinearGradient(colors: [Brand.gold.opacity(0.22), Brand.gold.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size.width * drawn)
                    }

                PriceLine(points: Self.points, closed: false)
                    .trim(from: 0, to: drawn)
                    .stroke(Brand.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Signal: dashed rule and pulsing dot.
                Path { path in
                    path.move(to: CGPoint(x: marker.x, y: 0))
                    path.addLine(to: CGPoint(x: marker.x, y: size.height))
                }
                .stroke(Brand.gold.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .opacity(showAlert ? 1 : 0)

                ZStack {
                    Circle()
                        .stroke(Brand.gold.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                        .scaleEffect(pulse ? 1.6 : 0.8)
                        .opacity(pulse ? 0 : 1)
                    Circle()
                        .fill(Brand.gold)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Brand.background, lineWidth: 2))
                }
                .position(marker)
                .opacity(showAlert ? 1 : 0)

                AlertChip()
                    .fixedSize()
                    .position(x: max(marker.x - 40, 120), y: max(size.height * 0.22, 26))
                    .opacity(showAlert ? 1 : 0)
                    .offset(y: showAlert ? 0 : 8)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: Moneta spots news about NVIDIA 28 minutes before the price rises.")
        .task {
            if reduceMotion {
                drawn = 1
                showAlert = true
                return
            }
            withAnimation(.easeInOut(duration: 1.6)) { drawn = 1 }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { showAlert = true }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    fileprivate static func point(_ index: Int, in size: CGSize) -> CGPoint {
        let step = size.width / CGFloat(points.count - 1)
        return CGPoint(x: CGFloat(index) * step, y: points[index] * size.height)
    }
}

/// The sample alert on the hero chart.
private struct AlertChip: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(Brand.gold, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("NVDA · Bullish")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.text)
                Text("Spotted 28 min before the move")
                    .font(.caption2)
                    .foregroundStyle(Brand.muted)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Color(hex: 0x1C2027), in: Capsule())
        .overlay(Capsule().strokeBorder(Brand.gold.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }
}

/// Smooth line through evenly spaced points; `closed` also closes it to the bottom for a fill.
private nonisolated struct PriceLine: Shape {
    let points: [CGFloat]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }
        let step = rect.width / CGFloat(points.count - 1)
        let pts = points.enumerated().map { CGPoint(x: CGFloat($0.offset) * step, y: $0.element * rect.height) }
        var path = Path()
        path.move(to: pts[0])
        for i in 1..<pts.count {
            let previous = pts[i - 1], current = pts[i]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            if i == pts.count - 1 { path.addLine(to: current) }
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

#Preview {
    AuthView()
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
