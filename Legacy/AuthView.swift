import SwiftUI

struct AuthView: View {
    @Environment(AuthService.self) private var auth

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case signUp = "Create account"
        var id: Self { self }
    }

    private enum Field: Hashable { case name, email, password }

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var focused: Field?

    private var canSubmit: Bool {
        let hasEmail = email.contains("@") && email.contains(".")
        let hasName = mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty
        return hasEmail && !password.isEmpty && hasName && !auth.isLoading
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                    .padding(.top, 40)

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    if mode == .signUp {
                        AuthField(systemImage: "person", placeholder: "Your name") {
                            TextField("", text: $name, prompt: prompt("Your name"))
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .focused($focused, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focused = .email }
                        }
                        .transition(.opacity)
                    }

                    AuthField(systemImage: "envelope", placeholder: "Email") {
                        TextField("", text: $email, prompt: prompt("Email"))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focused = .password }
                    }

                    AuthField(systemImage: "lock", placeholder: "Password") {
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("", text: $password, prompt: prompt("Password"))
                                } else {
                                    SecureField("", text: $password, prompt: prompt("Password"))
                                }
                            }
                            .textContentType(mode == .signUp ? .newPassword : .password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)

                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(width: 32, height: 32)
                            }
                            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        }
                    }
                }

                VStack(spacing: 12) {
                    PrimaryButton(
                        title: mode == .signIn ? "Sign in" : "Create account",
                        isEnabled: canSubmit,
                        isLoading: auth.isLoading,
                        action: submit
                    )

                    if let message = auth.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.bearish)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                }

                Spacer(minLength: 24)

                Text("Live web data by Context.dev")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: mode)
            .animation(.easeInOut(duration: 0.2), value: auth.errorMessage)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: mode) { _, _ in auth.errorMessage = nil }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Wordmark(size: 56)
                .padding(.vertical, 12)
            Text("The web knows first. Now so do you.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Theme.textTertiary)
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        Task {
            switch mode {
            case .signIn:
                await auth.signIn(email: email, password: password)
            case .signUp:
                await auth.signUp(email: email, password: password, displayName: name)
            }
        }
    }
}

private struct AuthField<Content: View>: View {
    let systemImage: String
    let placeholder: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 20)
            content
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                .strokeBorder(Theme.stroke)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
    }
}

#Preview {
    AuthView()
        .environment(AuthService())
}
