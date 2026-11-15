import Foundation
import Observation
import Supabase

nonisolated struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String?
    let onboarded: Bool

    enum CodingKeys: String, CodingKey {
        case id, onboarded
        case displayName = "display_name"
    }
}

/// Email + password auth and the signed-in user's profile.
@Observable
@MainActor
final class AuthService {
    private(set) var session: Session?
    private(set) var profile: Profile?
    /// True while a sign-in/up/out is running (and until the stored session has been read).
    private(set) var isLoading = true
    /// False until start() has read the stored session; the app shows a splash until then.
    private(set) var hasRestoredSession = false
    var errorMessage: String?

    @ObservationIgnored private var listener: Task<Void, Never>?

    var isSignedIn: Bool { session != nil }
    var userID: UUID? { session?.user.id }
    var email: String? { session?.user.email }

    // MARK: Lifecycle

    func start() async {
        guard listener == nil else { return }

        // Stored session, refreshed if it has expired. Nil when signed out.
        let current = try? await supabase.auth.session
        await apply(current)
        isLoading = false
        hasRestoredSession = true

        listener = Task { [weak self] in
            for await (_, session) in supabase.auth.authStateChanges {
                await self?.apply(session)
            }
        }
    }

    private func apply(_ newSession: Session?) async {
        let userChanged = newSession?.user.id != session?.user.id
        session = newSession
        if newSession == nil {
            profile = nil
        } else if userChanged || profile == nil {
            await loadProfile()
        }
    }

    // MARK: Auth

    func signUp(email: String, password: String, displayName: String) async {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        await run {
            let response = try await supabase.auth.signUp(
                email: Self.clean(email),
                password: password,
                data: ["display_name": .string(name)]
            )
            // Email confirmation is off, so a session comes back straight away.
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
        await run {
            try await supabase.auth.signOut()
            await self.apply(nil)
        }
    }

    // MARK: Profile

    func loadProfile() async {
        guard let userID else {
            profile = nil
            return
        }
        // The profile row is created by a trigger on sign-up; give it a moment if it's not there yet.
        for attempt in 0..<3 {
            do {
                profile = try await supabase
                    .from("profiles")
                    .select("id,display_name,onboarded")
                    .eq("id", value: userID)
                    .single()
                    .execute()
                    .value
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(600))
                } else {
                    errorMessage = "Couldn’t load your profile. \(Self.message(for: error))"
                }
            }
        }
    }

    func completeOnboarding() async {
        guard let userID else { return }
        do {
            try await supabase
                .from("profiles")
                .update(["onboarded": true])
                .eq("id", value: userID)
                .execute()
            await loadProfile()
        } catch {
            errorMessage = "Couldn’t save your progress. \(Self.message(for: error))"
        }
    }

    // MARK: Helpers

    private func run(_ work: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await work()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func clean(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func message(for error: Error) -> String {
        if let authError = error as? AuthError {
            switch authError {
            case .weakPassword:
                return "That password is too weak. Use at least 6 characters, mixing letters and numbers."
            case .sessionMissing:
                return "You’ve been signed out. Please sign in again."
            default:
                break
            }
            switch authError.errorCode {
            case .invalidCredentials:
                return "That email and password don’t match. Check them and try again."
            case .emailExists, .userAlreadyExists:
                return "An account with this email already exists. Try signing in instead."
            case .weakPassword:
                return "That password is too weak. Use at least 6 characters, mixing letters and numbers."
            case .validationFailed:
                return "Please enter a valid email address and password."
            case .overRequestRateLimit, .overEmailSendRateLimit:
                return "Too many attempts. Wait a minute and try again."
            case .signupDisabled:
                return "New sign-ups are turned off right now."
            case .emailNotConfirmed:
                return "Please confirm your email address first."
            default:
                return authError.message
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
                return "You appear to be offline. Check your connection and try again."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
