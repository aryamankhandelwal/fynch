import Foundation

struct PersistenceService {
    private static let showsKey = "fynch.tracked_shows_v1"
    private static let watchedKey = "fynch.watched_states_v1"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func saveShows(_ shows: [Show]) {
        guard let data = try? encoder.encode(shows) else { return }
        UserDefaults.standard.set(data, forKey: showsKey)
    }

    static func loadShows() -> [Show] {
        guard let data = UserDefaults.standard.data(forKey: showsKey),
              let shows = try? decoder.decode([Show].self, from: data)
        else { return [] }
        return shows
    }

    static func saveWatchedStates(_ states: [String: Bool]) {
        guard let data = try? encoder.encode(states) else { return }
        UserDefaults.standard.set(data, forKey: watchedKey)
    }

    static func loadWatchedStates() -> [String: Bool] {
        guard let data = UserDefaults.standard.data(forKey: watchedKey),
              let states = try? decoder.decode([String: Bool].self, from: data)
        else { return [:] }
        return states
    }
}
