import Foundation

// MARK: - Simulated market

/// A simulated trading day shared by the mock services.
///
/// The market clock starts at 14:55 and moves one minute per tick (every 2.5 s), so the day's
/// earlier signals are already in the past and new ones play out quickly. After a web change, the
/// price drifts by the seeded move over a few minutes, `lead` minutes later.
@MainActor
final class MockMarket {
    static let shared = MockMarket()

    static let tickInterval: Duration = .milliseconds(2500)

    private(set) var clock: Date
    let sessionOpen: Date

    private struct Reaction {
        let start: Date
        let end: Date
        let move: Double
    }

    private struct TickerState {
        var series: [PricePoint]
        /// Level the noise reverts to; moves with each reaction so moves stick.
        var anchor: Double
        var reactions: [Reaction]
        var rng: SeededRandom
        let seed: MockData.PriceSeed
    }

    private var states: [String: TickerState] = [:]
    private var subscribers: [UUID: (tickers: Set<String>, continuation: AsyncStream<PriceTick>.Continuation)] = [:]
    private var loop: Task<Void, Never>?

    private init() {
        sessionOpen = MockData.at(9, 30)
        clock = MockData.at(14, 55)
        for company in MockData.companies {
            guard let seed = MockData.prices[company.ticker] else { continue }
            var state = TickerState(series: [], anchor: seed.open, reactions: [], rng: SeededRandom(seed: company.ticker.stableSeed), seed: seed)
            for seeded in MockData.seeded where seeded.change.ticker == company.ticker && seeded.move != 0 {
                state.reactions.append(Self.reaction(after: seeded.change.detectedAt, lead: seeded.lead, move: seeded.move))
            }
            state.series = [PricePoint(date: sessionOpen, price: seed.open)]
            states[company.ticker] = state
        }
        var minute = sessionOpen.addingTimeInterval(60)
        while minute <= clock {
            for ticker in states.keys { appendPoint(ticker, at: minute) }
            minute = minute.addingTimeInterval(60)
        }
    }

    private static func reaction(after time: Date, lead: Int, move: Double) -> Reaction {
        let end = time.addingTimeInterval(Double(lead) * 60)
        let ramp = Double(min(6, max(lead - 1, 1))) * 60
        return Reaction(start: end.addingTimeInterval(-ramp), end: end, move: move)
    }

    private func appendPoint(_ ticker: String, at date: Date) {
        guard var state = states[ticker], let last = state.series.last else { return }
        let v = state.seed.volatility
        var price = last.price * (1 + Double.random(in: -v...v, using: &state.rng))
        // Gentle pull back towards the anchor so the noise doesn't wander off.
        price += (state.anchor - price) * 0.01
        for reaction in state.reactions where date > reaction.start && date <= reaction.end {
            let minutes = max(reaction.end.timeIntervalSince(reaction.start) / 60, 1)
            let step = pow(1 + reaction.move, 1 / minutes)
            price *= step
            state.anchor *= step
        }
        state.series.append(PricePoint(date: date, price: price))
        states[ticker] = state
    }

    /// Makes the price react `lead` minutes after a change.
    func addReaction(_ ticker: String, after time: Date, lead: Int, move: Double) {
        guard move != 0 else { return }
        states[ticker]?.reactions.append(Self.reaction(after: time, lead: lead, move: move))
    }

    func intraday(_ ticker: String) -> [PricePoint] { states[ticker]?.series ?? [] }

    func quote(_ ticker: String) -> Quote? {
        guard let state = states[ticker], let last = state.series.last else { return nil }
        return Quote(price: last.price, previousClose: state.seed.previousClose, updatedAt: last.date)
    }

    /// Daily (or hourly for 1W) history ending at today's price.
    func history(_ ticker: String, range: ChartRange) -> [PricePoint] {
        guard let state = states[ticker] else { return [] }
        if range == .day { return state.series }

        let today = state.series
        var rng = SeededRandom(seed: ticker.stableSeed &+ range.rawValue.stableSeed)
        let calendar = Calendar.current
        let stepsPerDay = range == .week ? 7 : 1
        let days: Int = switch range {
        case .week: 4
        case .month: 21
        case .quarter: 63
        default: 251
        }
        let dailyVol = 0.016 / Double(stepsPerDay).squareRoot()

        // Walk backwards from yesterday's close.
        var points: [PricePoint] = []
        var price = state.seed.previousClose
        var day = sessionOpen
        for _ in 0..<days {
            repeat {
                day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            } while calendar.isDateInWeekend(day)
            for step in (0..<stepsPerDay).reversed() {
                let date = calendar.date(bySettingHour: 10 + step, minute: 0, second: 0, of: day) ?? day
                points.append(PricePoint(date: date, price: price))
                price /= 1 + Double.random(in: -dailyVol...dailyVol, using: &rng) + 0.0004
            }
        }
        points.reverse()
        // Today: every 30 minutes for 1W, the latest price otherwise.
        if range == .week {
            points += today.enumerated().filter { $0.offset % 30 == 0 }.map(\.element)
        }
        if let last = today.last { points.append(last) }
        return points
    }

    // MARK: Live ticks

    func subscribe(_ tickers: Set<String>) -> AsyncStream<PriceTick> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<PriceTick>.makeStream()
        subscribers[id] = (tickers, continuation)
        continuation.onTermination = { _ in
            Task { @MainActor in MockMarket.shared.subscribers[id] = nil }
        }
        startLoop()
        return stream
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.advance()
            }
        }
    }

    private func advance() {
        clock = clock.addingTimeInterval(60)
        for ticker in states.keys { appendPoint(ticker, at: clock) }
        for (_, subscriber) in subscribers {
            for ticker in subscriber.tickers {
                if let point = states[ticker]?.series.last {
                    subscriber.continuation.yield(PriceTick(ticker: ticker, point: point))
                }
            }
        }
    }
}

// MARK: - Mock services

/// Prices from the simulated market.
/// Replace with your market-data provider (through your backend) for real quotes.
final class MockPriceService: PriceService {
    private let market = MockMarket.shared

    func searchCompanies(_ query: String) async throws -> [Company] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return MockData.companies }
        return MockData.companies.filter {
            $0.ticker.lowercased().contains(q) || $0.name.lowercased().contains(q) || $0.sector.lowercased().contains(q)
        }
    }

    func quote(for ticker: String) async throws -> Quote {
        guard let quote = market.quote(ticker) else { throw MockError.unknownTicker(ticker) }
        return quote
    }

    func history(for ticker: String, range: ChartRange) async throws -> [PricePoint] {
        market.history(ticker, range: range)
    }

    func ticks(for tickers: [String]) -> AsyncStream<PriceTick> {
        market.subscribe(Set(tickers))
    }

    func track(_ company: Company) async throws {}

    func defaultWatchlist() async -> [Company] {
        MockData.initialWatchlist.compactMap { ticker in MockData.companies.first { $0.ticker == ticker } }
    }
}

/// Seeded changes for today, plus a new one every 18–30 seconds for a random watched company.
final class MockWebMonitorService: WebMonitorService {
    private let market = MockMarket.shared
    private var watching: [String: Set<SignalSource>] = [:]
    private var rng = SystemRandomNumberGenerator()

    func startWatching(_ ticker: String, sources: Set<SignalSource>) async throws {
        watching[ticker] = sources
    }

    func stopWatching(_ ticker: String) async throws {
        watching[ticker] = nil
    }

    func recentChanges(for tickers: [String]) async throws -> [WebChange] {
        MockData.seeded
            .map(\.change)
            .filter { tickers.contains($0.ticker) && $0.detectedAt <= market.clock }
    }

    func changes() -> AsyncStream<WebChange> {
        let (stream, continuation) = AsyncStream<WebChange>.makeStream()
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 18...30)))
                guard let change = self?.makeLiveChange() else { continue }
                continuation.yield(change)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func makeLiveChange() -> WebChange? {
        let candidates = watching.filter { !$0.value.isEmpty }
        guard let (ticker, sources) = candidates.randomElement(using: &rng) else { return nil }
        let templates = MockData.liveTemplates.filter { sources.contains($0.source) }
        guard let template = templates.randomElement(using: &rng),
              let company = MockData.companies.first(where: { $0.ticker == ticker }) else { return nil }

        let slug = company.name.lowercased().replacingOccurrences(of: " ", with: "-")
        let change = WebChange(
            id: UUID(), ticker: ticker, source: template.source, detectedAt: market.clock,
            title: template.title,
            url: URL(string: "https://example.com/\(slug)/\(template.source.rawValue)")!,
            diff: template.diff.map { DiffLine(kind: $0.0, text: $0.1) },
            facts: template.facts
        )
        MockRegistry.shared.assessments[change.id] = SignalAssessment(impact: template.impact, why: template.why)
        let move = template.move.lowerBound == template.move.upperBound ? 0 : Double.random(in: template.move, using: &rng)
        market.addReaction(ticker, after: change.detectedAt, lead: Int.random(in: 12...35, using: &rng), move: move)
        return change
    }
}

/// Returns the verdicts registered for mock changes after a short "thinking" pause.
final class MockSignalAgent: SignalAgent {
    func assess(_ change: WebChange, company: Company) async throws -> SignalAssessment? {
        try await Task.sleep(for: .milliseconds(350))
        return MockRegistry.shared.assessments[change.id]
    }
}

enum MockError: Error {
    case unknownTicker(String)
}
