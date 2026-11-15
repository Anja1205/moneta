import Foundation
import Observation
import Supabase

/// A row of `profiles`. Created by the backend on sign-up; readable and writable only by its owner.
nonisolated struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var displayName: String?
    var onboarded: Bool

    enum CodingKeys: String, CodingKey {
        case id, onboarded
        case displayName = "display_name"
    }
}

/// Email + password auth and the signed-in user's profile. Inject with `.environment(auth)`.
@MainActor
@Observable
final class AuthService {
    private(set) var session: Session?
    private(set) var profile: Profile?
    /// True until `start()` has read the stored session. The app shows the splash meanwhile.
    private(set) var isCheckingSession = true
    /// A sign-in, sign-up, sign-out or onboarding save is running.
    private(set) var isLoading = false
    var errorMessage: String?
    /// Set when the profile couldn't be loaded, so the app can offer a retry instead of guessing.
    private(set) var profileError: String?

    @ObservationIgnored private var listener: Task<Void, Never>?

    var userID: UUID? { session?.user.id }
    var email: String? { session?.user.email }
    var displayName: String {
        if let name = profile?.displayName, !name.isEmpty { return name }
        return session?.user.userMetadata["display_name"]?.stringValue ?? ""
    }

    // MARK: Lifecycle

    /// Loads the stored session (refreshed if expired), then follows auth changes.
    func start() async {
        guard listener == nil else { return }

        let current = try? await supabase.auth.session
        await apply(current?.isExpired == false ? current : nil)
        isCheckingSession = false

        listener = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                // The initial session was handled above.
                guard event != .initialSession else { continue }
                await self?.apply(session)
            }
        }
    }

    private func apply(_ newSession: Session?) async {
        let userChanged = newSession?.user.id != session?.user.id
        let wasSignedIn = session != nil
        session = newSession
        if newSession == nil {
            // Signed out (or the session ended): take the Live Activity and alerts down with it.
            if wasSignedIn { await AlertService.shared.stop() }
            profile = nil
            profileError = nil
        } else if userChanged || profile == nil {
            if userChanged { profile = nil }
            await loadProfile()
        }
    }

    // MARK: Auth

    func signUp(name: String, email: String, password: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await run {
            let response = try await supabase.auth.signUp(
                email: Self.clean(email),
                password: password,
                data: ["display_name": .string(name)]
            )
            // Email confirmation is off, so the session comes back straight away.
            await self.apply(response.session)
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            let session = try await supabase.auth.signIn(email: Self.clean(email), password: password)
            await self.apply(session)
        }
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }
        // The local session is cleared even if the server can't be reached.
        try? await supabase.auth.signOut()
        await apply(nil)
    }

    // MARK: Profile

    func loadProfile() async {
        guard let id = session?.user.id else {
            profile = nil
            return
        }
        // The row is created by a trigger on sign-up; retry once in case it's not readable yet.
        for attempt in 0..<2 {
            do {
                let loaded: Profile = try await supabase
                    .from("profiles")
                    .select("id,display_name,onboarded")
                    .eq("id", value: id)
                    .single()
                    .execute()
                    .value
                guard session?.user.id == id else { return }
                profile = loaded
                profileError = nil
                return
            } catch {
                if attempt == 0, !(error is URLError) {
                    try? await Task.sleep(for: .milliseconds(600))
                    continue
                }
                guard session?.user.id == id else { return }
                profileError = Self.friendly(error)
            }
        }
    }

    /// Marks onboarding done (`profiles.onboarded = true`) and reloads the profile.
    func completeOnboarding() async {
        guard let id = session?.user.id else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await supabase
                .from("profiles")
                .update(["onboarded": true])
                .eq("id", value: id)
                .execute()
            profile?.onboarded = true
            await loadProfile()
        } catch {
            errorMessage = Self.friendly(error)
        }
    }

    // MARK: Helpers

    private func run(_ work: @escaping () async throws -> Void) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await work()
        } catch {
            errorMessage = Self.friendly(error)
        }
    }

    private static func clean(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static let networkError = "Couldn’t reach Moneta. Check your connection and try again."

    static func friendly(_ error: Error) -> String {
        if let auth = error as? AuthError {
            switch auth {
            case .weakPassword:
                return "Password must be at least 6 characters"
            case .api(let message, let code, _, _):
                if code == .invalidCredentials || message.localizedCaseInsensitiveContains("invalid login") {
                    return "Wrong email or password"
                }
                if code == .userAlreadyExists || code == .emailExists
                    || message.localizedCaseInsensitiveContains("already registered") {
                    return "This email is already registered"
                }
                if code == .weakPassword || message.localizedCaseInsensitiveContains("at least 6") {
                    return "Password must be at least 6 characters"
                }
                if code == .validationFailed || message.localizedCaseInsensitiveContains("invalid format") {
                    return "Enter a valid email address"
                }
            default:
                break
            }
        }
        return networkError
    }
}
