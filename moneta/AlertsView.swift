import SwiftUI
import UserNotifications

/// Signals at or above `Config.alertImpact`, newest first.
struct AlertsView: View {
    @Environment(SignalStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationsDenied = false

    private var alerts: [Signal] {
        store.signals.filter { $0.clampedImpact >= Config.alertImpact }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if notificationsDenied {
                        permissionBanner
                    }
                    if alerts.isEmpty {
                        emptyState
                    } else {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            LazyVStack(spacing: 12) {
                                ForEach(alerts) { signal in
                                    NavigationLink(value: signal) {
                                        SignalRow(
                                            signal: signal,
                                            isFresh: store.freshIds.contains(signal.id),
                                            now: context.date
                                        )
                                    }
                                    .buttonStyle(PressableCardStyle())
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: alerts.map(\.id))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .refreshable {
                await store.pollNow()
                await store.load()
            }
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LivePill(isLive: store.isLive)
                }
            }
            .navigationDestination(for: Signal.self) { signal in
                SignalDetailView(signal: signal, stock: store.stock(for: signal))
                    .toolbarBackground(Theme.background, for: .navigationBar)
            }
        }
        .task(id: scenePhase) { await refreshPermission() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.gold)
            Text("No alerts yet")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Signals with impact \(Config.alertImpact) or higher land here, and Moneta notifies you the moment one arrives.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .card()
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.slash")
                .foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications are off. Turn them on to get alerts as they happen.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.gold)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                .strokeBorder(Theme.gold.opacity(0.25))
        )
    }

    private func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }
}
