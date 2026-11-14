import SwiftUI

/// Splash → sign in → onboarding → main app, crossfading between them.
struct AppRootView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage(DataSource.storageKey) private var source: DataSource = .demo

    private enum Phase: Hashable {
        case splash
        case signedOut
        case profileError(String)
        case onboarding
        case main(UUID)
    }

    private var phase: Phase {
        if auth.isCheckingSession { return .splash }
        guard let userID = auth.userID else { return .signedOut }
        guard let profile = auth.profile else {
            if let message = auth.profileError { return .profileError(message) }
            return .splash
        }
        return profile.onboarded ? .main(userID) : .onboarding
    }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()

            switch phase {
            case .splash:
                SplashView()
                    .transition(.opacity)
            case .signedOut:
                AuthView()
                    .transition(.opacity)
            case .profileError(let message):
                ProfileErrorView(message: message)
                    .transition(.opacity)
            case .onboarding:
                OnboardingFlow()
                    .transition(.opacity)
            case .main(let userID):
                // A new user or data source gets a fresh store; signing out discards it.
                StoreHost(source: source, userID: userID)
                    .id("\(source.rawValue)-\(userID)")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: phase)
    }
}

/// Owns the store for one user and data source. Only created once the user is onboarded,
/// so prices and realtime start only then.
private struct StoreHost: View {
    @State private var store: MonetaStore

    init(source: DataSource, userID: UUID) {
        _store = State(initialValue: source.makeStore(userID: userID))
    }

    var body: some View {
        RootView()
            .environment(store)
            .task { await store.start() }
            .onDisappear { store.stop() }
    }
}

/// Signed in but the profile couldn't be read (usually offline).
private struct ProfileErrorView: View {
    let message: String
    @Environment(AuthService.self) private var auth
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            MonetaWordmark(size: 40)
            Text(message)
                .font(.callout)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
            Spacer()
            PrimaryButton("Try again", isLoading: isRetrying) {
                Task {
                    isRetrying = true
                    await auth.loadProfile()
                    isRetrying = false
                }
            }
            Button("Sign out") {
                Task { await auth.signOut() }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(Brand.muted)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, Brand.margin)
        .padding(.bottom, 8)
    }
}
