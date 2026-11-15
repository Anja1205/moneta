import SwiftUI

/// Pick a company, choose what Moneta watches and how loud alerts are, then start watching.
struct AddStockSheet: View {
    var preselected: Company?

    @Environment(MarketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Company] = []
    @State private var selected: Company?
    @State private var sources: Set<SignalSource> = Set(SignalSource.allCases)
    @State private var alertLevel: AlertLevel = .mediumUp
    @State private var isSaving = false
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    searchField
                    resultsList

                    VStack(alignment: .leading, spacing: Metrics.spacing) {
                        SectionTitle(text: "What Moneta watches", trailing: "\(sources.count) of \(SignalSource.allCases.count)")
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(SignalSource.allCases) { source in
                                SourceToggleTile(source: source, isOn: sources.contains(source)) {
                                    if sources.contains(source) { sources.remove(source) } else { sources.insert(source) }
                                }
                            }
                        }
                        if sources.isEmpty {
                            Text("Pick at least one source.")
                                .font(.mFootnote)
                                .foregroundStyle(Palette.down)
                        }
                    }

                    VStack(alignment: .leading, spacing: Metrics.spacing) {
                        SectionTitle(text: "Alert me for")
                        GlassSegmented(options: AlertLevel.allCases, selection: $alertLevel, title: \.label,
                                       accessibilityLabel: "Alert me for")
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .monetaScreen()
            .navigationTitle("Add stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    start()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(Palette.background)
                        } else {
                            Text(selected.map { "Start watching \($0.ticker)" } ?? "Pick a company")
                        }
                    }
                    .font(.mBodyStrong)
                    .foregroundStyle(Palette.background)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.amber)
                .disabled(selected == nil || sources.isEmpty || isSaving)
                .padding(.horizontal, Metrics.margin)
                .padding(.bottom, 8)
            }
        }
        .sensoryFeedback(.selection, trigger: sources)
        .sensoryFeedback(.selection, trigger: selected)
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            results = await store.search(query)
        }
        .onAppear {
            sources = store.defaultSettings.sources
            alertLevel = store.defaultSettings.alertLevel
            if let preselected, !store.isWatching(preselected.ticker) {
                selected = preselected
            }
            if preselected == nil { searchFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.muted)
            TextField("", text: $query, prompt: Text("Company or ticker").foregroundStyle(Palette.muted))
                .font(.mBody)
                .foregroundStyle(Palette.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, query.isEmpty ? 16 : 0)
        .frame(minHeight: 50)
        .background(Palette.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border))
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            Text("No companies match “\(query)”.")
                .font(.mCallout)
                .foregroundStyle(Palette.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(results) { company in
                    CompanyResultRow(
                        company: company,
                        isSelected: selected?.ticker == company.ticker,
                        isWatching: store.isWatching(company.ticker)
                    ) {
                        withAnimation(.snappy) {
                            selected = selected?.ticker == company.ticker ? nil : company
                        }
                    }
                }
            }
        }
    }

    private func start() {
        guard let selected, !sources.isEmpty else { return }
        isSaving = true
        Task {
            await store.addStock(selected, settings: WatchSettings(sources: sources, alertLevel: alertLevel))
            isSaving = false
            dismiss()
        }
    }
}

/// Selectable company row.
private struct CompanyResultRow: View {
    let company: Company
    let isSelected: Bool
    let isWatching: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                CompanyMark(company: company, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(company.name)
                        .font(.mBodyStrong)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(company.tickerLine)
                        .font(.mFootnote)
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                if isWatching {
                    CapsuleTag("Watching", systemImage: "eye", color: Palette.muted)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Palette.amber : Palette.border)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(14)
            .background(isSelected ? Palette.tint(Palette.amber) : Palette.card,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSelected ? Palette.amber : Palette.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(isWatching)
        .opacity(isWatching ? 0.6 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isWatching ? "Already watching" : "Selects \(company.name)")
    }
}

/// Toggle tile for one source; amber tint and border when on.
struct SourceToggleTile: View {
    let source: SignalSource
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: source.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOn ? Palette.amber : Palette.secondary)
                    Spacer()
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isOn ? Palette.amber : Palette.border)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(source.watchTitle)
                    .font(.mSubheadline)
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(isOn ? Palette.tint(Palette.amber) : Palette.card,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isOn ? Palette.amber : Palette.border, lineWidth: isOn ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityLabel(source.watchTitle)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddStockSheet(preselected: MockData.companies[3])
                .presentationDetents([.large])
        }
        .environment(MarketStore.preview())
        .preferredColorScheme(.dark)
}
