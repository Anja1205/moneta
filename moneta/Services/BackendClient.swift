import Foundation

/// Minimal Supabase REST + Edge Functions client over URLSession (no packages).
final class BackendClient {
    private let base: URL
    private let key: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(base: URL = BackendConfig.url, key: String = BackendConfig.publishableKey, session: URLSession = .shared) {
        self.base = base
        self.key = key
        self.session = session
    }

    /// GET /rest/v1/<table>?<query>
    func select<T: Decodable>(_ table: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: base.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        authorize(&request)
        return try await send(request)
    }

    /// POST /functions/v1/<name> with a JSON body.
    @discardableResult
    func invoke<T: Decodable>(_ function: String, body: some Encodable) async throws -> T {
        var request = URLRequest(url: base.appending(path: "functions/v1/\(function)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 45
        authorize(&request)
        return try await send(request)
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw BackendError.http(http.statusCode, body)
        }
        return try decoder.decode(T.self, from: data)
    }
}

enum BackendError: LocalizedError {
    case http(Int, String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): "Server returned \(code). \(body)"
        case .notFound(let what): "\(what) not found."
        }
    }
}

/// Accepts any JSON response when only success matters.
nonisolated struct IgnoredResponse: Decodable, Sendable {
    init(from decoder: Decoder) throws {}
}

/// Postgres `numeric` can arrive as a number or a string.
nonisolated extension KeyedDecodingContainer {
    func flexibleDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value.isFinite ? value : nil }
        if let raw = try? decodeIfPresent(String.self, forKey: key), let value = Double(raw), value.isFinite { return value }
        return nil
    }
}
