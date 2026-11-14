import SwiftUI
import UserNotifications

/// Signals at or above `Config.alertImpact`, newest first.
struct AlertsView: View {
    @Environment(SignalStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var confirmingSignOut = false
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
                    liveActivityCard
                    if alerts.isEmpty {
                        emptyState
                    } else {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            LazyVStack(spacing: 12) {
                                ForEach(alerts) { signal in
                                    NavigationLink(value: signal) {
                                        SignalRow(
                                            signal: signal,
                                            stock: store.stock(for: signal),
                                            isFresh: store.freshIds.contains(signal.id),
                                            now: context.date
                                        )
                                    }
                                    .buttonStyle(PressableCardStyle())
                                    .transition(.signalInsert)
                                }
                            }
                            .animation(.signalSpring, value: alerts.map(\.id))
                        }
                    }
                    accountSection
                    aboutNote
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .demoScrollAnchor()
            .background(Theme.background.ignoresSafeArea())
            .refreshable {
                await store.refreshAll()
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

    private var liveActivityCard: some View {
        let service = AlertService.shared
        let isOn = Binding(
            get: { service.isLiveActivityRunning },
            set: { on in
                if on {
                    let seed = store.signals.first { $0.clampedImpact >= AlertService.liveActivityImpact }
                    service.startLiveActivity(with: seed)
                } else {
                    Task { await service.stopLiveActivity() }
                }
            }
        )
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Activity")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Lock Screen and Dynamic Island show every signal with impact \(AlertService.liveActivityImpact)+.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "platter.filled.top.iphone")
                        .foregroundStyle(Theme.gold)
                }
            }
            .tint(Theme.gold)

            if let error = service.liveActivityError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.bearish)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Account")
                .padding(.top, 12)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(Theme.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Text(auth.email ?? "")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .padding(16)

                Divider().overlay(Theme.stroke)

                Button(role: .destructive) {
                    confirmingSignOut = true
                } label: {
                    HStack {
                        if auth.isLoading {
                            ProgressView().tint(Theme.bearish)
                        } else {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        Spacer()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.bearish)
                    .padding(16)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.98))
                .disabled(auth.isLoading)
            }
            .card(padding: 0)
        }
        .confirmationDialog("Sign out of Moneta?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var displayName: String {
        let name = auth.profile?.displayName?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Moneta member" : name
    }

    private var aboutNote: some View {
        Text("Named for Juno Moneta, from *monere*, ‘to warn.’ Live data by Context.dev.")
            .font(Theme.caption)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.gold)
            Text("No alerts yet")
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Signals with impact \(Config.alertImpact) or higher land here, and Moneta notifies you the moment one arrives.")
                .font(Theme.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .card()
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.slash")
                .foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications are off. Turn them on to get alerts as they happen.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
