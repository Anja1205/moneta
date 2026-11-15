import SwiftUI

/// Companies picked during onboarding, in the order they were picked.
@Observable
final class OnboardingSelection {
    private(set) var companies: [Company] = []

    var count: Int { companies.count }

    func contains(_ ticker: String) -> Bool {
        companies.contains { $0.ticker == ticker }
    }

    func toggle(_ company: Company) {
        if let index = companies.firstIndex(where: { $0.ticker == company.ticker }) {
            companies.remove(at: index)
        } else {
            companies.append(company)
        }
    }
}

/// Welcome → pick stocks → set up the watchlist.
struct OnboardingFlow: View {
    private enum Step: Int, CaseIterable {
        case welcome, pick, setup
    }

    @State private var step: Step = .welcome
    @State private var forward = true
    @State private var selection = OnboardingSelection()
    @State private var isSettingUp = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Brand.margin)
                .padding(.top, 8)

            ZStack {
                switch step {
                case .welcome:
                    WelcomePage { go(to: .pick) }
                        .transition(slide)
                case .pick:
                    PickStocksPage(selection: selection) { go(to: .setup) }
                        .transition(slide)
                case .setup:
                    SetupPage(companies: selection.companies, isWorking: $isSettingUp)
                        .transition(slide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Brand.background.ignoresSafeArea())
    }

    private var slide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var showsBack: Bool {
        step == .pick || (step == .setup && !isSettingUp)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                go(to: Step(rawValue: step.rawValue - 1) ?? .welcome)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Brand.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(showsBack ? 1 : 0)
            .disabled(!showsBack)
            .accessibilityLabel("Back")
            .accessibilityHidden(!showsBack)

            StepProgress(current: step.rawValue, total: Step.allCases.count)

            // Balances the back button so the bar stays centred.
            Color.clear.frame(width: 44, height: 44)
        }
        .animation(.easeOut(duration: 0.2), value: showsBack)
    }

    private func go(to target: Step) {
        guard target != step else { return }
        // Set the direction first so the outgoing page uses it too.
        forward = target.rawValue > step.rawValue
        Task { @MainActor in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = target }
        }
    }
}

/// Thin capsules; gold for done and current steps.
private struct StepProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Brand.gold : Color.white.opacity(0.12))
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

#Preview {
    OnboardingFlow()
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
