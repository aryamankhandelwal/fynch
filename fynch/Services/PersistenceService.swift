import Foundation

struct PersistenceService {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // Per-user keys
    private static func showsKey(userId: String)   -> String { "fynch.shows.\(userId).v1" }
    private static func watchedKey(userId: String) -> String { "fynch.watchedStates.\(userId).v1" }

    static func saveShows(_ shows: [Show], userId: String) {
        guard let data = try? encoder.encode(shows) else { return }
        UserDefaults.standard.set(data, forKey: showsKey(userId: userId))
    }

    static func loadShows(userId: String) -> [Show] {
        guard let data   = UserDefaults.standard.data(forKey: showsKey(userId: userId)),
              let shows  = try? decoder.decode([Show].self, from: data)
        else { return [] }
        return shows
    }

    static func saveWatchedStates(_ states: [String: Bool], userId: String) {
        guard let data = try? encoder.encode(states) else { return }
        UserDefaults.standard.set(data, forKey: watchedKey(userId: userId))
    }

    static func loadWatchedStates(userId: String) -> [String: Bool] {
        guard let data   = UserDefaults.standard.data(forKey: watchedKey(userId: userId)),
              let states = try? decoder.decode([String: Bool].self, from: data)
        else { return [:] }
        return states
    }

    // MARK: - Migration (pre-multi-user data)

    private static let legacyShowsKey   = "fynch.tracked_shows_v1"
    private static let legacyWatchedKey = "fynch.watched_states_v1"

    static func loadLegacyShows() -> [Show]? {
        guard let data  = UserDefaults.standard.data(forKey: legacyShowsKey),
              let shows = try? decoder.decode([Show].self, from: data),
              !shows.isEmpty
        else { return nil }
        return shows
    }

    static func loadLegacyWatchedStates() -> [String: Bool] {
        guard let data   = UserDefaults.standard.data(forKey: legacyWatchedKey),
              let states = try? decoder.decode([String: Bool].self, from: data)
        else { return [:] }
        return states
    }

    static func clearLegacyData() {
        UserDefaults.standard.removeObject(forKey: legacyShowsKey)
        UserDefaults.standard.removeObject(forKey: legacyWatchedKey)
    }
}
