import SwiftUI

struct SettingsView: View {
    @Environment(MonetaStore.self) private var store
    @AppStorage(DataSource.storageKey) private var source: DataSource = .demo

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    group("Alerts for new stocks") {
                        GlassSegmented(options: AlertLevel.allCases, selection: $store.defaultSettings.alertLevel,
                                       title: \.label, accessibilityLabel: "Default alert level")
                    }

                    group("Watch by default") {
                        Card(padding: 6) {
                            VStack(spacing: 0) {
                                ForEach(SignalSource.allCases) { source in
                                    Toggle(isOn: Binding(
                                        get: { store.defaultSettings.sources.contains(source) },
                                        set: { on in
                                            if on { store.defaultSettings.sources.insert(source) } else { store.defaultSettings.sources.remove(source) }
                                        }
                                    )) {
                                        Label(source.watchTitle, systemImage: source.symbol)
                                            .font(.mBody)
                                            .foregroundStyle(Palette.text)
                                    }
                                    .tint(Palette.amber)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 50)
                                    if source != SignalSource.allCases.last { Divider().overlay(Palette.border) }
                                }
                            }
                        }
                        .sensoryFeedback(.selection, trigger: store.defaultSettings.sources) { _, _ in store.hapticsEnabled }
                    }

                    group("Feedback") {
                        Card(padding: 6) {
                            Toggle(isOn: $store.hapticsEnabled) {
                                Label("Haptics for new alerts", systemImage: "iphone.radiowaves.left.and.right")
                                    .font(.mBody)
                                    .foregroundStyle(Palette.text)
                            }
                            .tint(Palette.amber)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 50)
                        }
                        .sensoryFeedback(.selection, trigger: store.hapticsEnabled)
                    }

                    if !store.mutedKeys.isEmpty {
                        group("Muted") {
                            Card(padding: 6) {
                                VStack(spacing: 0) {
                                    ForEach(store.mutedKeys.sorted(), id: \.self) { key in
                                        mutedRow(key)
                                    }
                                }
                            }
                        }
                    }

                    group("Data") {
                        GlassSegmented(options: DataSource.allCases, selection: $source,
                                       title: \.label, accessibilityLabel: "Data source")
                        Card {
                            Label {
                                Text(source.explanation)
                                    .font(.mCallout)
                                    .foregroundStyle(Palette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: source == .demo ? "testtube.2" : "server.rack")
                                    .foregroundStyle(Palette.amber)
                            }
                        }
                    }
                    .sensoryFeedback(.selection, trigger: source) { _, _ in store.hapticsEnabled }

                    Text("Named for Juno Moneta, from Latin *monere*, “to warn”.")
                        .font(.mFootnote)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .monetaScreen()
            .navigationTitle("Settings")
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.mSubheadline)
                .foregroundStyle(Palette.muted)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func mutedRow(_ key: String) -> some View {
        let parts = key.split(separator: "|").map(String.init)
        let source = parts.count > 1 ? SignalSource(rawValue: parts[1]) : nil
        return HStack {
            Label("\(parts.first ?? "") · \(source?.label ?? "")", systemImage: source?.symbol ?? "bell.slash")
                .font(.mBody)
                .foregroundStyle(Palette.text)
            Spacer()
            Button("Unmute") { store.unmute(key) }
                .font(.mSubheadline)
                .foregroundStyle(Palette.amber)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 12)
    }
}

#Preview {
    SettingsView()
        .environment(MonetaStore.preview())
        .preferredColorScheme(.dark)
}
