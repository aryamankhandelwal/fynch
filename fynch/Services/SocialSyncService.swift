import Foundation

/// Reads and writes social data (feed events, friend requests, friendships, user profiles)
/// in Firestore via the REST API, following the same pattern as CloudSyncService.
actor SocialSyncService {
    private let base: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        base = "https://firestore.googleapis.com/v1/projects/\(FirebaseConfig.projectId)/databases/(default)/documents"
    }

    // MARK: - User Profiles

    func saveUserProfile(userId: String, username: String, idToken: String) async {
        guard let jsonString = encode(UserProfile(userId: userId, username: username)) else { return }
        let url = URL(string: "\(base)/userProfiles/\(username)")!
        try? await patch(url: url, jsonString: jsonString, idToken: idToken)
    }

    /// Returns all registered usernames that contain `prefix`, excluding `currentUsername`.
    func searchUsers(prefix: String, currentUsername: String, idToken: String) async -> [UserProfile] {
        let query = prefix.lowercased()
        guard !query.isEmpty else { return [] }

        // 1. Try listing the whole collection (succeeds only if security rules permit it)
        var fromList: [UserProfile] = []
        let listUrl = URL(string: "\(base)/userProfiles")!
        var listReq = URLRequest(url: listUrl)
        listReq.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        if let (data, response) = try? await URLSession.shared.data(for: listReq),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let docs = json["documents"] as? [[String: Any]] {
            fromList = docs
                .compactMap { decode(UserProfile.self, from: $0) }
                .filter { $0.username != currentUsername && $0.username.localizedCaseInsensitiveContains(query) }
                .sorted { $0.username < $1.username }
        }
        if !fromList.isEmpty { return fromList }

        // 2. Fallback: direct document fetch by exact lowercased username.
        //    This handles restrictive security rules that block collection listing.
        let directUrl = URL(string: "\(base)/userProfiles/\(query)")!
        var directReq = URLRequest(url: directUrl)
        directReq.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        if let (directData, directResp) = try? await URLSession.shared.data(for: directReq),
           (directResp as? HTTPURLResponse)?.statusCode == 200,
           let singleDoc = try? JSONSerialization.jsonObject(with: directData) as? [String: Any],
           let profile = decode(UserProfile.self, from: singleDoc),
           profile.username != currentUsername {
            return [profile]
        }
        return []
    }

    // MARK: - Feed Events

    func saveFeedEvent(_ event: FeedEvent, idToken: String) async {
        guard let jsonString = encode(event) else { return }
        let url = URL(string: "\(base)/feedEvents/\(event.id.uuidString)")!
        try? await patch(url: url, jsonString: jsonString, idToken: idToken)
    }

    /// Fetches all feed events then filters to the provided usernames client-side.
    func fetchFeedEvents(forUsernames usernames: [String], idToken: String) async -> [FeedEvent] {
        guard !usernames.isEmpty else { return [] }
        let url = URL(string: "\(base)/feedEvents")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return [] }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return [] }
        guard status == 200 else { return [] }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let docs = json["documents"] as? [[String: Any]] ?? []
        let usernameSet = Set(usernames)
        return docs
            .compactMap { decode(FeedEvent.self, from: $0) }
            .filter { usernameSet.contains($0.username) }
    }

    func deleteFeedEvent(id: UUID, idToken: String) async {
        let url = URL(string: "\(base)/feedEvents/\(id.uuidString)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }

    func deleteAllFeedEvents(forUsername username: String, idToken: String) async {
        let events = await fetchFeedEvents(forUsernames: [username], idToken: idToken)
        await withTaskGroup(of: Void.self) { group in
            for event in events {
                group.addTask { await self.deleteFeedEvent(id: event.id, idToken: idToken) }
            }
        }
    }

    // MARK: - Friend Requests

    func saveFriendRequest(_ request: FriendRequest, idToken: String) async {
        guard let jsonString = encode(request) else { return }
        let url = URL(string: "\(base)/friendRequests/\(request.id.uuidString)")!
        try? await patch(url: url, jsonString: jsonString, idToken: idToken)
    }

    func fetchFriendRequests(toUsername: String, idToken: String) async -> [FriendRequest] {
        let url = URL(string: "\(base)/friendRequests")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return [] }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return [] }
        guard status == 200 else { return [] }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let docs = json["documents"] as? [[String: Any]] ?? []
        return docs
            .compactMap { decode(FriendRequest.self, from: $0) }
            .filter { $0.to == toUsername }
    }

    func deleteFriendRequest(_ request: FriendRequest, idToken: String) async {
        let url = URL(string: "\(base)/friendRequests/\(request.id.uuidString)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Friendships

    func saveFriendship(
        userId: String,
        friendUserId: String,
        friendUsername: String,
        idToken: String
    ) async {
        let record = FriendshipRecord(
            username: friendUsername,
            userId: friendUserId,
            since: Date().timeIntervalSince1970
        )
        guard let jsonString = encode(record) else { return }
        let url = URL(string: "\(base)/friendships/\(userId)/friends/\(friendUserId)")!
        try? await patch(url: url, jsonString: jsonString, idToken: idToken)
    }

    func fetchFriends(userId: String, idToken: String) async -> [FriendshipRecord] {
        let url = URL(string: "\(base)/friendships/\(userId)/friends")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return [] }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return [] }
        guard status == 200 else { return [] }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let docs = json["documents"] as? [[String: Any]] ?? []
        return docs.compactMap { decode(FriendshipRecord.self, from: $0) }
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
