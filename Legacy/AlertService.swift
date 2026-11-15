 import ActivityKit
import Observation
import UIKit
import UserNotifications

/// Haptics, local notifications and the Moneta Live Activity for signals arriving over Realtime.
@Observable
@MainActor
final class AlertService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertService()

    /// Signals at or above this impact update the Live Activity.
    static let liveActivityImpact = 3

    private(set) var isLiveActivityRunning = false
    private(set) var liveActivityError: String?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private let impact = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private let notify = UINotificationFeedbackGenerator()
    @ObservationIgnored private var activity: Activity<MonetaAttributes>?

    private override init() {
        super.init()
        // Pick up an activity that survived an app relaunch.
        activity = Activity<MonetaAttributes>.activities.first { $0.activityState == .active }
        isLiveActivityRunning = activity != nil
    }

    var liveActivitiesAllowed: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: Notifications

    /// Becomes the notification delegate and asks for permission. Returns whether alerts are allowed.
    @discardableResult
    func requestPermission() async -> Bool {
        center.delegate = self
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func handle(_ signal: Signal) {
        let isAlert = signal.clampedImpact >= Config.alertImpact
        if isAlert {
            notify.notificationOccurred(signal.direction == .bearish ? .warning : .success)
        } else {
            impact.impactOccurred()
        }

        if signal.clampedImpact >= Self.liveActivityImpact {
            updateLiveActivity(with: signal)
        }

        guard isAlert else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(signal.ticker) · \(signal.direction.label)"
        content.subtitle = signal.title
        content.body = signal.why
        content.sound = .default
        content.threadIdentifier = signal.ticker
        content.userInfo = ["signal_id": signal.id.uuidString]

        let request = UNNotificationRequest(identifier: signal.id.uuidString, content: content, trigger: nil)
        center.add(request) { _ in }
    }

    // MARK: Live Activity

    /// Starts the Live Activity, showing `signal` if given, otherwise a "watching" state.
    func startLiveActivity(with signal: Signal? = nil) {
        liveActivityError = nil
        guard liveActivitiesAllowed else {
            liveActivityError = "Live Activities are turned off for Moneta in Settings."
            return
        }
        if activity != nil {
            if let signal { updateLiveActivity(with: signal) }
            return
        }
        let state = signal.map(Self.state(for:)) ?? .watching
        do {
            activity = try Activity.request(
                attributes: MonetaAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            isLiveActivityRunning = true
        } catch {
            liveActivityError = "Couldn’t start the Live Activity. \(error.localizedDescription)"
            isLiveActivityRunning = false
        }
    }

    func stopLiveActivity() async {
        for running in Activity<MonetaAttributes>.activities {
            await running.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        isLiveActivityRunning = false
    }

    private func updateLiveActivity(with signal: Signal) {
        guard let activity else { return }
        let content = ActivityContent(state: Self.state(for: signal), staleDate: nil)
        Task {
            if activity.activityState == .active {
                await activity.update(content)
            } else {
                self.activity = nil
                self.isLiveActivityRunning = false
            }
        }
    }

    private static func state(for signal: Signal) -> MonetaAttributes.ContentState {
        MonetaAttributes.ContentState(
            ticker: signal.ticker,
            direction: signal.direction.rawValue,
            why: signal.why,
            impact: signal.clampedImpact,
            updatedAt: signal.detectedDate ?? .now
        )
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show banners even while Moneta is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
