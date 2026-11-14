import SwiftUI

struct AddStockView: View {
    @Environment(SignalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var ticker = ""
    @State private var name = ""
    @State private var website = ""
    @State private var isSubmitting = false
    @State private var step = 0
    @State private var finished = false
    @State private var errorMessage: String?
    @State private var successTrigger = 0
    @FocusState private var focused: Field?

    private enum Field { case ticker, name, website }

    private static let steps = ["Finding company", "Getting brand", "Scanning live news", "Scoring signals"]

    private var canSubmit: Bool {
        !ticker.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ticker", text: $ticker, prompt: Text("NVDA").foregroundStyle(Theme.textTertiary))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .ticker)
                        .submitLabel(.next)
                        .onSubmit { focused = .name }
                        .onChange(of: ticker) { _, value in
                            let upper = value.uppercased()
                            if upper != value { ticker = upper }
                        }
                    TextField("Company name", text: $name, prompt: Text("Nvidia").foregroundStyle(Theme.textTertiary))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .website }
                    TextField("Website", text: $website, prompt: Text("nvidia.com (optional)").foregroundStyle(Theme.textTertiary))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focused, equals: .website)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } header: {
                    Text("Company")
                } footer: {
                    Text("Moneta watches its news, investor relations, careers and pricing pages, and scores every change.")
                }
                .listRowBackground(Theme.card)
                .disabled(isSubmitting)

                if isSubmitting || finished {
                    Section {
                        ForEach(Self.steps.indices, id: \.self) { index in
                            ProgressStepRow(title: Self.steps[index], state: state(of: index))
                        }
                    }
                    .listRowBackground(Theme.card)
                    .transition(.opacity)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.bearish)
                    }
                    .listRowBackground(Theme.bearish.opacity(0.08))
                }

                Section {
                    Button(action: submit) {
                        Text(isSubmitting ? "Watching…" : "Start watching")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(Theme.background)
                            .background(
                                Theme.gold.opacity(canSubmit || isSubmitting ? 1 : 0.4),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.textPrimary)
            .animation(.easeInOut(duration: 0.25), value: isSubmitting)
            .animation(.easeInOut(duration: 0.25), value: errorMessage)
            .navigationTitle("Track a stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
        }
        .sensoryFeedback(.success, trigger: successTrigger)
        .interactiveDismissDisabled(isSubmitting)
        .onAppear { focused = .ticker }
    }

    private func state(of index: Int) -> ProgressStepRow.State {
        if finished || index < step { return .done }
        return index == step ? .running : .waiting
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        errorMessage = nil
        finished = false
        step = 0
        isSubmitting = true

        let ticker = ticker, name = name
        let website = website.trimmingCharacters(in: .whitespaces)

        // Advance the visual steps while the request runs; the last one waits for the result.
        let stepTask = Task {
            for _ in 1..<Self.steps.count {
                try await Task.sleep(for: .seconds(1.6))
                withAnimation(.snappy) { step += 1 }
            }
        }

        Task {
            let error = await store.addStock(ticker: ticker, name: name, domain: website.isEmpty ? nil : website)
            stepTask.cancel()
            if let error {
                isSubmitting = false
                errorMessage = error
                step = 0
            } else {
                withAnimation(.snappy) { finished = true }
                successTrigger += 1
                try? await Task.sleep(for: .seconds(0.6))
                isSubmitting = false
                dismiss()
            }
        }
    }
}

private struct ProgressStepRow: View {
    enum State { case waiting, running, done }

    let title: String
    let state: State

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                switch state {
                case .waiting:
                    Circle()
                        .strokeBorder(Theme.textTertiary, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                case .running:
                    ProgressView()
                        .tint(Theme.gold)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.bullish)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(.subheadline.weight(state == .running ? .semibold : .regular))
                .foregroundStyle(state == .waiting ? Theme.textTertiary : Theme.textPrimary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == .done ? "Done" : state == .running ? "In progress" : "Waiting")
    }
}
