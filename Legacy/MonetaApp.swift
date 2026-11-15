import SwiftUI

@main
struct MonetaApp: App {
    @State private var auth = AuthService()
    @State private var store = SignalStore()

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(auth)
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                // Layouts are checked up to xxLarge; larger accessibility sizes are capped there.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .task { await auth.start() }
        }
    }
}

/// Splash → AuthView → OnboardingView → main tabs, driven by AuthService.
struct AppRouter: View {
    @Environment(AuthService.self) private var auth
    @Environment(SignalStore.self) private var store

    private enum Route: Equatable { case splash, auth, onboarding, main }

    private var route: Route {
        #if DEBUG
        switch DemoMode.route {
        case "main": return .main
        case "onboarding": return .onboarding
        case "auth": return .auth
        default: break
        }
        #endif
        guard auth.hasRestoredSession else { return .splash }
        guard auth.session != nil else { return .auth }
        guard let profile = auth.profile else { return .splash }
        return profile.onboarded ? .main : .onboarding
    }

    var body: some View {
        ZStack {
            switch route {
            case .splash: SplashView()
            case .auth: AuthView()
            case .onboarding: OnboardingView()
            case .main: RootView()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: route)
        .onChange(of: auth.userID) { old, new in
            // Signed out, or a different user signed in: drop the previous user's data.
            guard old != nil, old != new else { return }
            Task {
                await store.reset()
                await AlertService.shared.stopLiveActivity()
            }
        }
    }
}

/// Gold wordmark shown while the stored session and profile load.
struct SplashView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Wordmark(size: 56)
            if auth.hasRestoredSession, auth.session != nil, auth.profile == nil, let message = auth.errorMessage {
                // Signed in but the profile couldn't load.
                VStack(spacing: 12) {
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.bearish)
                    HStack(spacing: 20) {
                        Button("Try again") {
                            auth.errorMessage = nil
                            Task { await auth.loadProfile() }
                        }
                        .fontWeight(.semibold)
                        Button("Sign out") { Task { await auth.signOut() } }
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 32)
            } else {
                ProgressView().tint(Theme.gold)
                    .opacity(auth.hasRestoredSession ? 1 : 0)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}

/// Main tabs. Loads the user's data and starts Realtime only once shown.
struct RootView: View {
    @Environment(SignalStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var didStart = false
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            WatchlistView()
                .tabItem { Label("Watchlist", systemImage: "eye") }
                .tag(0)
            FeedView()
                .tabItem { Label("Live Feed", systemImage: "dot.radiowaves.left.and.right") }
                .tag(1)
            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
                .tag(2)
        }
        .task {
            #if DEBUG
            if DemoMode.isMain {
                store.seedDemo()
                tab = ["feed": 1, "alerts": 2][DemoMode.screen] ?? 0
                return
            }
            #endif
            store.onNewSignal = { AlertService.shared.handle($0) }
            await store.load()
            await store.startRealtime()
            didStart = true
            // No prompt if already answered during onboarding.
            await AlertService.shared.requestPermission()
        }
        .onChange(of: scenePhase) { _, phase in
            guard didStart else { return }
            switch phase {
            case .active:
                Task {
                    await store.load()
                    await store.startRealtime()
                }
            case .background:
                Task { await store.stopRealtime() }
            default:
                break
            }
        }
    }
}
