import Foundation
import Observation

@Observable
final class SocialStore {

    var feedEvents: [FeedEvent] = []
    var friends: [String: [String]] = [:]   // username → [username]
    var friendRequests: [FriendRequest] = []

    // Set by fynchApp after session is established
    var socialSyncService: SocialSyncService? = nil
    var currentUserId: String = ""
    var currentUsername: String = ""
    var currentIdToken: String = ""

    private enum Keys {
        // v2 keys because FriendRequest schema changed (added userId fields)
        static let feed           = "fynch.feed"
        static let friends        = "fynch.friends"
        static let friendRequests = "fynch.friendRequests.v2"
    }

    init() {
        feedEvents     = decode([FeedEvent].self,        from: Keys.feed)           ?? []
        friends        = decode([String: [String]].self, from: Keys.friends)        ?? [:]
        friendRequests = decode([FriendRequest].self,    from: Keys.friendRequests) ?? []
    }

    // MARK: - Firestore sync

    @MainActor
    func loadFromFirestore() async {
        guard !currentUserId.isEmpty, let svc = socialSyncService else { return }
        let userId   = currentUserId
        let username = currentUsername
        let token    = currentIdToken

        async let fetchedFriends  = svc.fetchFriends(userId: userId, idToken: token)
        async let fetchedRequests = svc.fetchFriendRequests(toUsername: username, idToken: token)
        let (firestoreFriends, firestoreRequests) = await (fetchedFriends, fetchedRequests)

        let friendUsernames = firestoreFriends.map { $0.username }
        friends[username] = friendUsernames
        friendRequests = firestoreRequests

        let visibleUsernames = [username] + friendUsernames
        let events = await svc.fetchFeedEvents(forUsernames: visibleUsernames, idToken: token)
        let remoteIds = Set(events.map { $0.id })
        let localOnlyEvents = feedEvents.filter { !remoteIds.contains($0.id) }
        feedEvents = (events + localOnlyEvents).sorted { $0.timestamp > $1.timestamp }

        encode(feedEvents,     to: Keys.feed)
        encode(friends,        to: Keys.friends)
        encode(friendRequests, to: Keys.friendRequests)
    }

    func searchUsers(prefix: String) async -> [UserProfile] {
        guard let svc = socialSyncService else { return [] }
        return await svc.searchUsers(
            prefix: prefix,
            currentUsername: currentUsername,
            idToken: currentIdToken
        )
    }

    // MARK: - Feed

    func logWatchedEpisodes(
        username: String,
        showId: String,
        showName: String,
        season: Int,
        episode: Int?,
        count: Int,
        lastEpisodeTitle: String?,
        isFirstEpisodeOfShow: Bool,
        isLastOfSeason: Bool,
        isLastOfShow: Bool
    ) {
        let event: FeedEvent
        if count == 1 {
            let type: FeedEventType
            if isFirstEpisodeOfShow {
                type = .started
            } else if isLastOfShow {
                type = .finishedShow
            } else if isLastOfSeason {
                type = .finishedSeason
            } else {
                type = .watchedEpisode
            }
            event = FeedEvent(
                id: UUID(),
                username: username,
                type: type,
                showName: showName,
                episodeCount: nil,
                episodeTitle: lastEpisodeTitle,
                season: season,
                episode: episode,
                timestamp: Date()
            )
            feedEvents.insert(event, at: 0)
        } else {
            // Collapse into an existing watchedBatch for the same user+show within 5 minutes
            if let idx = feedEvents.firstIndex(where: { ev in
                ev.username == username &&
                ev.showName == showName &&
                ev.type == .watchedBatch &&
                Date().timeIntervalSince(ev.timestamp) < 300
            }) {
                feedEvents[idx].episodeCount = (feedEvents[idx].episodeCount ?? 0) + count
                encode(feedEvents, to: Keys.feed)
                let updatedEvent = feedEvents[idx]
                let token = currentIdToken
                if let svc = socialSyncService {
                    Task { await svc.saveFeedEvent(updatedEvent, idToken: token) }
                }
                return
            } else {
                event = FeedEvent(
                    id: UUID(),
                    username: username,
                    type: .watchedBatch,
                    showName: showName,
                    episodeCount: count,
                    episodeTitle: lastEpisodeTitle,
                    season: season,
                    episode: nil,
                    timestamp: Date()
                )
                feedEvents.insert(event, at: 0)
            }
        }
        encode(feedEvents, to: Keys.feed)
        let token = currentIdToken
        if let svc = socialSyncService {
            Task { await svc.saveFeedEvent(event, idToken: token) }
        }
    }

    func clearFeed() {
        let username = currentUsername
        let token = currentIdToken
        feedEvents.removeAll { $0.username == username }
        encode(feedEvents, to: Keys.feed)
        if let svc = socialSyncService {
            Task { await svc.deleteAllFeedEvents(forUsername: username, idToken: token) }
        }
    }

    func clearAllFeeds() {
        let allUsernames = Set(feedEvents.map { $0.username })
        feedEvents.removeAll()
        encode(feedEvents, to: Keys.feed)
        let token = currentIdToken
        if let svc = socialSyncService {
            Task {
                for username in allUsernames {
                    await svc.deleteAllFeedEvents(forUsername: username, idToken: token)
                }
            }
        }
    }

    // MARK: - Friends

    func areFriends(_ a: String, _ b: String) -> Bool {
        friends[a]?.contains(b) ?? false
    }

    func hasPendingRequest(from sender: String, to recipient: String) -> Bool {
        friendRequests.contains { $0.from == sender && $0.to == recipient }
    }

    func sendFriendRequest(to recipient: String, recipientUserId: String) {
        let sender   = currentUsername
        let senderId = currentUserId
        guard sender != recipient else { return }
        guard !areFriends(sender, recipient) else { return }
        guard !hasPendingRequest(from: sender, to: recipient) else { return }

        let request = FriendRequest(
            id: UUID(),
            from: sender,
            fromUserId: senderId,
            to: recipient,
            toUserId: recipientUserId,
            timestamp: Date()
        )
        friendRequests.append(request)
        encode(friendRequests, to: Keys.friendRequests)

        let token = currentIdToken
        if let svc = socialSyncService {
            Task { await svc.saveFriendRequest(request, idToken: token) }
        }
    }

    func acceptFriendRequest(_ request: FriendRequest) {
        friends[request.from, default: []].append(request.to)
        friends[request.to, default: []].append(request.from)
        encode(friends, to: Keys.friends)

        friendRequests.removeAll { $0.id == request.id }
        encode(friendRequests, to: Keys.friendRequests)

        let token = currentIdToken
        if let svc = socialSyncService {
            Task {
                await svc.saveFriendship(
                    userId: request.toUserId,
                    friendUserId: request.fromUserId,
                    friendUsername: request.from,
                    idToken: token
                )
                await svc.saveFriendship(
                    userId: request.fromUserId,
                    friendUserId: request.toUserId,
                    friendUsername: request.to,
                    idToken: token
                )
                await svc.deleteFriendRequest(request, idToken: token)
            }
        }
    }

    func declineFriendRequest(_ request: FriendRequest) {
        friendRequests.removeAll { $0.id == request.id }
        encode(friendRequests, to: Keys.friendRequests)

        let token = currentIdToken
        if let svc = socialSyncService {
            Task { await svc.deleteFriendRequest(request, idToken: token) }
        }
    }

    // MARK: - Persistence

    private func decode<T: Decodable>(_ type: T.Type, from key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, to key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
