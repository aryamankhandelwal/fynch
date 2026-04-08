import Foundation

enum CloudError: LocalizedError {
    case serverError(Int)
    var errorDescription: String? {
        if case .serverError(let c) = self { return "Cloud sync error (\(c))." }
        return nil
    }
}

/// Reads and writes per-user data in Firestore via the REST API.
/// Shows and watchedStates are stored as JSON strings inside a single "data" field,
/// which lets us reuse the existing Codable implementations without any Firestore type mapping.
actor CloudSyncService {
    private let base: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        base = "https://firestore.googleapis.com/v1/projects/\(FirebaseConfig.projectId)/databases/(default)/documents"
    }

    // MARK: - Shows

    func loadShows(userId: String, idToken: String) async throws -> [Show] {
        let url = URL(string: "\(base)/users/\(userId)/shows")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        if http.statusCode == 404 { return [] }
        guard http.statusCode == 200 else { throw CloudError.serverError(http.statusCode) }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let docs  = json["documents"] as? [[String: Any]] ?? []
        return docs.compactMap { decode(Show.self, from: $0) }
    }

    func saveShow(_ show: Show, userId: String, idToken: String) async throws {
        guard let jsonString = encode(show) else { return }
        let url = URL(string: "\(base)/users/\(userId)/shows/\(show.id)")!
        try await patch(url: url, jsonString: jsonString, idToken: idToken)
    }

    func deleteShow(showId: String, userId: String, idToken: String) async throws {
        let url = URL(string: "\(base)/users/\(userId)/shows/\(showId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        guard http.statusCode == 200 || http.statusCode == 404 else {
            throw CloudError.serverError(http.statusCode)
        }
    }

    // MARK: - Watched States

    func loadWatchedStates(userId: String, idToken: String) async throws -> [String: Bool] {
        let url = URL(string: "\(base)/users/\(userId)/watchedStates/states")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        if http.statusCode == 404 { return [:] }
        guard http.statusCode == 200 else { throw CloudError.serverError(http.statusCode) }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let fields   = json["fields"]           as? [String: Any],
              let dataField = fields["data"]           as? [String: Any],
              let jsonStr   = dataField["stringValue"] as? String,
              let jsonData  = jsonStr.data(using: .utf8),
              let states    = try? decoder.decode([String: Bool].self, from: jsonData)
        else { return [:] }
        return states
    }

    func saveWatchedStates(_ states: [String: Bool], userId: String, idToken: String) async throws {
        guard let jsonString = encode(states) else { return }
        let url = URL(string: "\(base)/users/\(userId)/watchedStates/states")!
        try await patch(url: url, jsonString: jsonString, idToken: idToken)
    }

    // MARK: - Migration

    func migrateData(shows: [Show], watchedStates: [String: Bool], userId: String, idToken: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for show in shows {
                group.addTask { try await self.saveShow(show, userId: userId, idToken: idToken) }
            }
            try await group.waitForAll()
        }
        try await saveWatchedStates(watchedStates, userId: userId, idToken: idToken)
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decode<T: Decodable>(_ type: T.Type, from doc: [String: Any]) -> T? {
        guard let fields    = doc["fields"]           as? [String: Any],
              let dataField  = fields["data"]           as? [String: Any],
              let jsonStr    = dataField["stringValue"] as? String,
              let jsonData   = jsonStr.data(using: .utf8),
              let value      = try? decoder.decode(T.self, from: jsonData)
        else { return nil }
        return value
    }

    private func patch(url: URL, jsonString: String, idToken: String) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "fields": ["data": ["stringValue": jsonString]]
        ])
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        guard http.statusCode == 200 else { throw CloudError.serverError(http.statusCode) }
    }
}
