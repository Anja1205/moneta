import SwiftUI

/// Timeline card: a direction bar on the left edge, numbered pin, "time · source", the direction
/// badge, title, the why, then the impact meter and the price move after it.
/// Impact 5 gets a soft glow in the direction colour; a fresh or re-scored card flashes amber.
struct SignalTimelineCard: View {
    let signal: Signal
    let number: Int
    let reaction: MarketReaction?
    var company: Company? = nil
    var isFresh = false
    var isMuted = false

    private var directionColor: Color { Palette.direction(signal.direction) }
    private var isMajor: Bool { signal.impact == .major }

    private var borderColor: Color {
        if isFresh { return Palette.amber }
        if isMajor { return directionColor.opacity(0.55) }
        return Palette.border
    }

    var body: some View {
        Card(border: borderColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    SignalPin(number: number, impact: signal.impact)
                    VStack(alignment: .leading, spacing: 1) {
                        if let company {
                            Text(company.ticker)
                                .font(.mSubheadline)
                                .foregroundStyle(Palette.text)
                        }
                        Text("\(Fmt.when(signal.time)) · \(signal.source.label)")
                            .font(.mFootnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if isMuted {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .accessibilityLabel("Muted")
                    }
                    DirectionBadge(direction: signal.direction)
                }
                Text(signal.title)
                    .font(.mHeadline)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(signal.why)
                    .font(.mCallout)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .center) {
                    ImpactMeter(impact: signal.impact, direction: signal.direction)
                    Spacer(minLength: 8)
                    moveView
                }
                .padding(.top, 2)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(directionColor)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .shadow(color: isFresh ? Palette.amber.opacity(0.25) : isMajor ? directionColor.opacity(0.28) : .clear,
                radius: isMajor && !isFresh ? 14 : 16)
        .animation(.easeOut(duration: 0.35), value: isFresh)
        .animation(.easeOut(duration: 0.35), value: signal)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the signal")
    }

    @ViewBuilder
    private var moveView: some View {
        if let reaction, reaction.at != nil {
            ChangeCapsule(fraction: reaction.move)
        } else if let reaction, reaction.settled {
            // No meaningful move within the hour.
            ChangeCapsule(fraction: 0)
        } else {
            CapsuleTag("Watching", systemImage: "clock", color: Palette.muted)
        }
    }
}

#Preview {
    let seeded = MockData.seeded[0]
    let signal = Signal(id: seeded.change.id, ticker: "VNTR", source: .investor, impact: .major,
                        time: seeded.change.detectedAt, title: seeded.change.title, why: seeded.assessment.why,
                        url: seeded.change.url, facts: seeded.change.facts, diff: seeded.change.diff,
                        direction: .bullish)
    SignalTimelineCard(signal: signal, number: 1,
                       reaction: MarketReaction(signalTime: signal.time, move: 0.028, at: signal.time.addingTimeInterval(1680)))
        .padding()
        .background(Palette.background)
}
