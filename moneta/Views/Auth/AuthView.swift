import SwiftUI

/// Sign in or create an account with email and password.
struct AuthView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case create = "Create account"
        var id: Self { self }
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

    private var isValid: Bool {
        isEmailValid && password.count >= 6
            && (mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 28) {
                        header
                            .padding(.top, 40)

                        Picker("Mode", selection: $mode.animation(.spring(response: 0.4, dampingFraction: 0.85))) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        fields

                        VStack(spacing: 12) {
                            PrimaryButton(mode.rawValue, isLoading: auth.isLoading, action: submit)
                                .disabled(!isValid)
                                .id("submit")

                            if let error = auth.errorMessage {
                                Text(error)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Brand.bearish)
                                    .multilineTextAlignment(.center)
                                    .modifier(ShakeEffect(travel: shakes))
                                    .transition(.opacity)
                            }
                        }

                        Spacer(minLength: 16)

                        Text("Live web data by Context.dev")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                            .padding(.bottom, 8)
                    }
                    .padding(.horizontal, Brand.margin)
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
        .background(Brand.background.ignoresSafeArea())
        .animation(.easeOut(duration: 0.2), value: auth.errorMessage)
        .onChange(of: mode) { _, _ in auth.errorMessage = nil }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            GoldGlow(size: 340, intensity: 0.28, period: 4)
            VStack(spacing: 10) {
                MonetaWordmark(size: 52)
                Text("The web knows first. Now so do you.")
                    .font(.callout)
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(height: 170)
    }

    // MARK: Fields

    private var fields: some View {
        VStack(spacing: Brand.spacing) {
            if mode == .create {
                fieldCard(icon: "person") {
                    TextField("", text: $name, prompt: prompt("Name"))
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .name)
                        .onSubmit { focus = .email }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            fieldCard(icon: "envelope") {
                TextField("", text: $email, prompt: prompt("Email"))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            }

            fieldCard(icon: "lock") {
                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("", text: $password, prompt: prompt("Password"))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("", text: $password, prompt: prompt("Password"))
                        }
                    }
                    .textContentType(mode == .create ? .newPassword : .password)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit(submit)

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
            }
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Brand.muted)
    }

    private func fieldCard<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Brand.muted)
                .frame(width: 20)
                .accessibilityHidden(true)
            content()
                .font(.body)
                .foregroundStyle(Brand.text)
                .tint(Brand.gold)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 56)
        .brandCard()
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

#Preview {
    AuthView()
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
