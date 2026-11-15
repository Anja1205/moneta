import ActivityKit
import Foundation
import Observation
import UIKit
import UserNotifications

/// The Moneta Live Activity (Lock Screen + Dynamic Island) and local notifications for new alerts.
///
/// Updates come from the app while it's running (foreground, or briefly in the background).
/// Updating it while the app is closed needs ActivityKit push updates from the backend.
@MainActor
@Observable
final class AlertService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertService()

    private(set) var isLiveActivityRunning = false

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var activity: Activity<MonetaAttributes>?

    /// Alerts that arrive close together are collected for this long and sent as one notification.
    private static let batchWindow: Duration = .seconds(4)
    /// After a notification for a stock, further ones for it wait this long (high impact excepted).
    private static let tickerCooldown: TimeInterval = 10 * 60
    /// The same story (syndicated copies, or tagged to several stocks) only notifies once in this time.
    private static let duplicateWindow: TimeInterval = 6 * 3600

    private struct Pending {
        let signal: Signal
        let logoURL: URL?
    }

    @ObservationIgnored private var pending: [Pending] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var lastNotified: [String: Date] = [:]
    @ObservationIgnored private var recentStories: [String: Date] = [:]

    private override init() {
        super.init()
        // Pick up an activity that survived an app relaunch.
        activity = Activity<MonetaAttributes>.activities.first { $0.activityState == .active }
        isLiveActivityRunning = activity != nil
    }

    // MARK: Lifecycle

    /// Called when the main app opens: becomes the notification delegate, asks for permission
    /// (no prompt if already answered) and starts or refreshes the Live Activity.
    func start(latest: Signal?) async {
        center.delegate = self
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        startLiveActivity(with: latest)
    }

    /// Called on sign-out.
    func stop() async {
        for running in Activity<MonetaAttributes>.activities {
            await running.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        isLiveActivityRunning = false
        flushTask?.cancel()
        flushTask = nil
        pending = []
        lastNotified = [:]
        recentStories = [:]
        center.removeAllDeliveredNotifications()
    }

    // MARK: Alerts

    /// A new signal at or above the stock's alert level. Alerts are collected for a few seconds,
    /// then the most important one goes to the Live Activity and they leave as one notification.
    func handle(_ signal: Signal, logoURL: URL?) {
        pending.append(Pending(signal: signal, logoURL: logoURL))
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.batchWindow)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        let batch = pending
        pending = []
        flushTask = nil
        let now = Date()
        recentStories = recentStories.filter { now.timeIntervalSince($0.value) < Self.duplicateWindow }

        // Most important first; drop stories already sent (same headline on another stock or copy).
        var fresh: [Pending] = []
        for item in batch.sorted(by: { ($0.signal.impact, $0.signal.time) > ($1.signal.impact, $1.signal.time) }) {
            let key = Self.storyKey(item.signal.title)
            guard recentStories[key] == nil else { continue }
            recentStories[key] = now
            fresh.append(item)
        }
        guard let top = fresh.first else { return }

        if activity == nil {
            startLiveActivity(with: top.signal)
        } else {
            update(with: top.signal)
        }

        // One notification per stock per cooldown, unless it's high impact.
        let toNotify = fresh.filter { item in
            item.signal.impact >= .high
                || lastNotified[item.signal.ticker].map { now.timeIntervalSince($0) > Self.tickerCooldown } ?? true
        }
        guard let lead = toNotify.first else { return }
        for item in toNotify { lastNotified[item.signal.ticker] = now }

        let content = UNMutableNotificationContent()
        if toNotify.count == 1 {
            content.title = "\(lead.signal.ticker) · \(lead.signal.direction.label) · \(lead.signal.impact.label)"
            content.subtitle = lead.signal.title
            content.body = lead.signal.why
            content.threadIdentifier = lead.signal.ticker
            content.userInfo = ["signal_id": lead.signal.id.uuidString, "ticker": lead.signal.ticker]
        } else {
            let tickers = Array(NSOrderedSet(array: toNotify.map(\.signal.ticker))) as? [String] ?? []
            let shown = tickers.prefix(3).joined(separator: ", ")
            let more = tickers.count > 3 ? " +\(tickers.count - 3)" : ""
            content.title = "\(toNotify.count) new signals · \(shown)\(more)"
            content.subtitle = "\(lead.signal.ticker): \(lead.signal.title)"
            content.body = lead.signal.why
            content.threadIdentifier = "moneta.batch"
            content.userInfo = ["ticker": lead.signal.ticker]
        }
        content.sound = .default
        content.interruptionLevel = toNotify.contains { $0.signal.impact == .major } ? .timeSensitive : .active
        if let attachment = await Self.logoAttachment(lead.logoURL) {
            content.attachments = [attachment]
        }
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Lowercased letters and digits of the headline's start: copies of one story share it.
    private static func storyKey(_ title: String) -> String {
        String(title.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(48))
    }

    /// The company logo as a notification thumbnail. Nil for SVGs or when it can't be loaded.
    private nonisolated static func logoAttachment(_ url: URL?) async -> UNNotificationAttachment? {
        guard let url, url.pathExtension.lowercased() != "svg" else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let png = UIImage(data: data)?.pngData() else { return nil }
            let file = FileManager.default.temporaryDirectory.appending(path: "logo-\(UUID().uuidString).png")
            try png.write(to: file)
            return try UNNotificationAttachment(identifier: "logo", url: file, options: nil)
        } catch {
            return nil
        }
    }

    // MARK: Live Activity

    private func startLiveActivity(with signal: Signal?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity, activity.activityState == .active {
            if let signal { update(with: signal) }
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
            activity = nil
            isLiveActivityRunning = false
        }
    }

    private func update(with signal: Signal) {
        guard let activity else { return }
        guard activity.activityState == .active else {
            // Dismissed by the user or ended by the system: start a fresh one.
            self.activity = nil
            startLiveActivity(with: signal)
            return
        }
        let content = ActivityContent(state: Self.state(for: signal), staleDate: nil, relevanceScore: Double(signal.impact.rawValue))
        Task { await Self.push(content) }
    }

    /// Looks the activity up again off the main actor; `Activity` isn't Sendable.
    private nonisolated static func push(_ content: ActivityContent<MonetaAttributes.ContentState>) async {
        for running in Activity<MonetaAttributes>.activities where running.activityState == .active {
            await running.update(content)
        }
    }

    private static func state(for signal: Signal) -> MonetaAttributes.ContentState {
        MonetaAttributes.ContentState(
            ticker: signal.ticker,
            direction: signal.direction.rawValue,
            why: signal.why,
            impact: signal.impact.rawValue,
            updatedAt: signal.time
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
