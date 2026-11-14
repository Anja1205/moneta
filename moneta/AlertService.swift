import UIKit
import UserNotifications

/// Haptics and local notifications for signals arriving over Realtime.
@MainActor
final class AlertService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertService()

    private let center = UNUserNotificationCenter.current()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    private override init() {
        super.init()
    }

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

    // MARK: UNUserNotificationCenterDelegate

    /// Show banners even while Moneta is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
