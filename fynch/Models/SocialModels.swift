import Foundation

struct FeedEvent: Codable, Identifiable {
    let id: UUID
    let username: String
    let type: FeedEventType
    let showName: String
    var episodeCount: Int?
    let episodeTitle: String?
    let season: Int?
    let episode: Int?   // episode number for "Season X Episode Y" display
    let timestamp: Date
}

enum FeedEventType: String, Codable {
    case started
    case watchedBatch
    case watchedEpisode
    case finishedSeason
    case finishedShow
}

struct FriendRequest: Codable, Identifiable {
    let id: UUID
    let from: String
    let fromUserId: String
    let to: String
    let toUserId: String
    let timestamp: Date
}

struct UserProfile: Codable {
    let userId: String
    let username: String
}

struct FriendshipRecord: Codable {
    let username: String
    let userId: String
    let since: Double
}
