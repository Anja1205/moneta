import Foundation

/// Assessments that arrive with backend signals, handed from the monitor to the agent.
@MainActor
final class BackendSignalCache {
    static let shared = BackendSignalCache()
    var assessments: [UUID: SignalAssessment] = [:]
}

/// Web changes from the backend's `signals` table. The backend watches the web (news, investor
/// pages… via Context.dev) on its own schedule and scores each row with an AI agent. This polls
/// for new rows every 30 s; Realtime INSERTs and UPDATEs come through `LiveAccount`.
final class BackendWebMonitorService: WebMonitorService {
    private let client: BackendClient
    private var watching: Set<String> = []
    private var newest: Date?
    private let pollInterval: Duration = .seconds(30)
    /// How far back the timeline starts.
    private let lookback: TimeInterval = 3 * 86_400

    init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    func startWatching(_ ticker: String, sources: Set<SignalSource>) async throws {
        watching.insert(ticker.uppercased())
    }

    func stopWatching(_ ticker: String) async throws {
        watching.remove(ticker.uppercased())
    }

    func recentChanges(for tickers: [String]) async throws -> [WebChange] {
        let since = Date().addingTimeInterval(-lookback)
        let changes = try await fetch(tickers: tickers.map { $0.uppercased() }, after: since, limit: 80)
        if let latest = changes.map(\.detectedAt).max(), newest.map({ latest > $0 }) ?? true { newest = latest }
        return changes
    }

    func changes() -> AsyncStream<WebChange> {
        let (stream, continuation) = AsyncStream<WebChange>.makeStream()
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(30))
                guard let self, !watching.isEmpty else { continue }
                let after = newest ?? Date().addingTimeInterval(-lookback)
                guard let found = try? await fetch(tickers: Array(watching), after: after, limit: 40) else { continue }
                for change in found.sorted(by: { $0.detectedAt < $1.detectedAt }) {
                    continuation.yield(change)
                }
                if let latest = found.map(\.detectedAt).max() { newest = latest }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // MARK: Fetching

    typealias Row = BackendSignalRow

    /// A Realtime row as a change, with its verdict cached for the agent. Nil for unusable or
    /// non-English rows.
    static func change(fromRealtime row: Row) -> WebChange? {
        guard PlainText.isLatinScript(row.title + " " + (row.description ?? "")),
              let detected = BackendDate.parse(row.detected_at) else { return nil }
        let change = change(from: row, detectedAt: detected)
        BackendSignalCache.shared.assessments[change.id] = assessment(from: row)
        return change
    }
}

/// A `signals` row. Columns are snake_case as in the table.
nonisolated struct BackendSignalRow: Decodable, Sendable {
        let id: UUID
        let ticker: String
        let source_kind: String?
        let source_name: String?
        let title: String
        let description: String?
        let url: String?
        let detected_at: String
        let published_at: String?
        let impact: Int?
        let direction: String?
        let why: String?
        let is_new: Bool?
}

extension BackendWebMonitorService {

    private func fetch(tickers: [String], after: Date, limit: Int) async throws -> [WebChange] {
        guard !tickers.isEmpty else { return [] }
        let rows: [Row] = try await client.select("signals", query: [
            URLQueryItem(name: "select", value: "id,ticker,source_kind,source_name,title,description,url,detected_at,published_at,impact,direction,why,is_new"),
            URLQueryItem(name: "ticker", value: "in.(\(tickers.joined(separator: ",")))"),
            URLQueryItem(name: "detected_at", value: "gt.\(after.formatted(.iso8601))"),
            URLQueryItem(name: "order", value: "detected_at.desc"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ])
        // The backend can store one story several times (syndicated copies): keep the first.
        var seenTitles = Set<String>()
        return rows.compactMap { row in
            // English only: skip stories written in Korean, Chinese, Japanese, Cyrillic…
            guard PlainText.isLatinScript(row.title + " " + (row.description ?? "")) else { return nil }
            let key = row.ticker.uppercased() + "|" + row.title.lowercased()
            guard seenTitles.insert(key).inserted, let detected = BackendDate.parse(row.detected_at) else { return nil }
            let change = Self.change(from: row, detectedAt: detected)
            BackendSignalCache.shared.assessments[change.id] = Self.assessment(from: row)
            return change
        }
    }

    private static func source(_ kind: String?) -> SignalSource {
        switch kind {
        case "ir_page", "demo": .investor
        case "careers": .careers
        case "pricing": .pricing
        case "x", "twitter": .x
        case "changelog", "product": .changelog
        default: .news
        }
    }

    private static func change(from row: Row, detectedAt: Date) -> WebChange {
        let source = source(row.source_kind)
        let text = row.description.map(PlainText.clean) ?? ""
        let diff: [DiffLine] = text.isEmpty ? [] : [DiffLine(kind: source == .news ? .unchanged : .added, text: text)]
        var facts: [String] = []
        if let name = row.source_name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { facts.append(name) }
        if let published = row.published_at.flatMap(BackendDate.parse), detectedAt.timeIntervalSince(published) > 3600 {
            facts.append("Published \(Fmt.when(published))")
        }
        let url = row.url.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased()) ? $0 : nil }
        return WebChange(
            id: row.id, ticker: row.ticker.uppercased(), source: source, detectedAt: detectedAt,
            title: PlainText.clean(row.title), url: url, diff: diff, facts: facts, isNew: row.is_new ?? true
        )
    }

    private static func assessment(from row: Row) -> SignalAssessment {
        let why = row.why.map(PlainText.clean)
        return SignalAssessment(
            impact: Impact(score: row.impact ?? 3),
            why: why?.isEmpty == false ? why! : "No explanation from the agent yet.",
            direction: Direction(row.direction)
        )
    }
}

/// The backend already ran the LLM on each signal; this returns its verdict.
final class BackendSignalAgent: SignalAgent {
    func assess(_ change: WebChange, company: Company) async throws -> SignalAssessment? {
        BackendSignalCache.shared.assessments[change.id]
    }
}

/// Strips markdown and whitespace noise from scraped page text.
nonisolated enum PlainText {
    static func clean(_ raw: String) -> String {
        var s = raw
        // [text](url) → text, ![alt](img) → ""
        s = s.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // Headings, emphasis, bullets.
        s = s.replacingOccurrences(of: #"(?m)^\s*#{1,6}\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\*\*|__|`)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?m)^\s*[-*•]\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 420 { s = String(s.prefix(417)).trimmingCharacters(in: .whitespaces) + "…" }
        return s
    }

    /// True when at least 80% of the letters are Latin (A–Z plus accented forms).
    /// Tickers and brand names in Latin letters inside foreign text don't tip it.
    static func isLatinScript(_ text: String) -> Bool {
        var latin = 0
        var other = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF: latin += 1
            default: other += 1
            }
        }
        let total = latin + other
        return total == 0 || Double(latin) / Double(total) >= 0.8
    }
}
