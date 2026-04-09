import SwiftUI
import Observation

@Observable
final class AppState {
    var shows: [Show] = []
    var watchedStates: [String: Bool] = [:]
    var isAddingShow: Bool = false
    var isRefreshing: Bool = false
    var isRestoringSession: Bool = true
    var currentUser: AuthSession? = nil

    var isLoggedIn: Bool { currentUser != nil }

    @ObservationIgnored private let authService: AuthService
    @ObservationIgnored private let cloudService: CloudSyncService

    init(authService: AuthService, cloudService: CloudSyncService) {
        self.authService  = authService
        self.cloudService = cloudService
    }

    // MARK: - Auth

    @MainActor
    func signIn(username: String, password: String) async throws {
        let session = try await authService.signIn(username: username, password: password)
        currentUser = session
        KeychainService.save(session)

        // One-time migration of pre-multi-user data
        let migrated = UserDefaults.standard.bool(forKey: "fynch.migrationCompleted")
        if !migrated, let legacyShows = PersistenceService.loadLegacyShows() {
            let legacyStates = PersistenceService.loadLegacyWatchedStates()
            shows        = legacyShows
            watchedStates = legacyStates
            PersistenceService.saveShows(legacyShows, userId: session.userId)
            PersistenceService.saveWatchedStates(legacyStates, userId: session.userId)
            let userId   = session.userId
            let idToken  = session.idToken
            Task {
                try? await cloudService.migrateData(
                    shows: legacyShows,
                    watchedStates: legacyStates,
                    userId: userId,
                    idToken: idToken
                )
                PersistenceService.clearLegacyData()
                UserDefaults.standard.set(true, forKey: "fynch.migrationCompleted")
            }
        } else {
            await loadUserData()
        }
    }

    /// Called on launch when a saved Keychain session is found.
    @MainActor
    func restoreSession(_ session: AuthSession) {
        currentUser   = session
        KeychainService.save(session)
        shows         = PersistenceService.loadShows(userId: session.userId)
        watchedStates = PersistenceService.loadWatchedStates(userId: session.userId)
    }

    /// Fetches fresh data from Firestore and merges into local state.
    @MainActor
    func loadUserData() async {
        guard let session = currentUser else { return }
        do {
            async let cloudShows  = cloudService.loadShows(userId: session.userId, idToken: session.idToken)
            async let cloudStates = cloudService.loadWatchedStates(userId: session.userId, idToken: session.idToken)
            let (fetchedShows, fetchedStates) = try await (cloudShows, cloudStates)
            shows         = fetchedShows
            watchedStates = fetchedStates
            PersistenceService.saveShows(fetchedShows, userId: session.userId)
            PersistenceService.saveWatchedStates(fetchedStates, userId: session.userId)
        } catch {
            #if DEBUG
            print("[fynch] loadUserData error: \(error)")
            #endif
        }
    }

    func signOut() {
        shows         = []
        watchedStates = [:]
        currentUser   = nil
        KeychainService.delete()
    }

    // MARK: - Key

    static func watchKey(showId: String, season: Int, episode: Int) -> String {
        "\(showId)-S\(season)E\(episode)"
    }

    // MARK: - Air date

    private static let airDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func isAired(_ airDate: String?) -> Bool {
        guard let iso = airDate, !iso.isEmpty else { return true }
        guard let date = airDateFormatter.date(from: iso) else { return true }
        return date <= Date()
    }

    // MARK: - Queries

    func isWatched(showId: String, season: Int, episode: Int) -> Bool {
        watchedStates[AppState.watchKey(showId: showId, season: season, episode: episode)] ?? false
    }

    func nextEpisode(for show: Show) -> Episode? {
        for season in show.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber }) {
            for episode in season.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }) {
                guard AppState.isAired(episode.airDate) else { continue }
                if !isWatched(showId: show.id, season: season.seasonNumber, episode: episode.episodeNumber) {
                    return episode
                }
            }
        }
        return nil
    }

    func nextUnairedEpisode(for show: Show) -> Episode? {
        for season in show.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber }) {
            for episode in season.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }) {
                if !AppState.isAired(episode.airDate) { return episode }
            }
        }
        return nil
    }

    func isCompleted(_ show: Show) -> Bool { nextEpisode(for: show) == nil }

    func episodesRemaining(for show: Show) -> Int {
        show.seasons.reduce(0) { total, season in
            total + season.episodes.filter {
                AppState.isAired($0.airDate) &&
                !isWatched(showId: show.id, season: season.seasonNumber, episode: $0.episodeNumber)
            }.count
        }
    }

    func unairedEpisodesCount(for show: Show) -> Int {
        show.seasons.reduce(0) { total, season in
            total + season.episodes.filter { !AppState.isAired($0.airDate) }.count
        }
    }

    func statusLabel(for show: Show) -> String {
        let remaining = episodesRemaining(for: show)
        if remaining == 0 {
            let unaired = unairedEpisodesCount(for: show)
            if unaired > 0 {
                return "Caught up · \(unaired) left in season"
            }
            return "Caught up"
        }
        return remaining == 1 ? "1 new episode" : "\(remaining) new episodes"
    }

    // MARK: - Mutations

    func toggleWatched(showId: String, season: Int, episode: Int) {
        let key = AppState.watchKey(showId: showId, season: season, episode: episode)
        watchedStates[key] = !(watchedStates[key] ?? false)
        guard let session = currentUser else { return }
        PersistenceService.saveWatchedStates(watchedStates, userId: session.userId)
        let states  = watchedStates
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.saveWatchedStates(states, userId: userId, idToken: idToken) }
    }

    func addShow(_ show: Show) {
        guard !shows.contains(where: { $0.id == show.id }) else { return }
        shows.append(show)
        guard let session = currentUser else { return }
        PersistenceService.saveShows(shows, userId: session.userId)
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.saveShow(show, userId: userId, idToken: idToken) }
    }

    func markSeasonWatched(showId: String, season: Season) {
        for ep in season.episodes {
            watchedStates[AppState.watchKey(showId: showId, season: season.seasonNumber, episode: ep.episodeNumber)] = true
        }
        guard let session = currentUser else { return }
        PersistenceService.saveWatchedStates(watchedStates, userId: session.userId)
        let states  = watchedStates
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.saveWatchedStates(states, userId: userId, idToken: idToken) }
    }

    func markSeasonUnwatched(showId: String, season: Season) {
        for ep in season.episodes {
            watchedStates[AppState.watchKey(showId: showId, season: season.seasonNumber, episode: ep.episodeNumber)] = false
        }
        guard let session = currentUser else { return }
        PersistenceService.saveWatchedStates(watchedStates, userId: session.userId)
        let states  = watchedStates
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.saveWatchedStates(states, userId: userId, idToken: idToken) }
    }

    func isSeasonWatched(showId: String, season: Season) -> Bool {
        season.episodes.allSatisfy {
            isWatched(showId: showId, season: season.seasonNumber, episode: $0.episodeNumber)
        }
    }

    func isShowFullyWatched(_ show: Show) -> Bool {
        show.seasons.allSatisfy { isSeasonWatched(showId: show.id, season: $0) }
    }

    func markShowWatched(_ show: Show) {
        for season in show.seasons {
            for ep in season.episodes {
                watchedStates[AppState.watchKey(showId: show.id, season: season.seasonNumber, episode: ep.episodeNumber)] = true
            }
        }
        guard let session = currentUser else { return }
        PersistenceService.saveWatchedStates(watchedStates, userId: session.userId)
        let states  = watchedStates
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.saveWatchedStates(states, userId: userId, idToken: idToken) }
    }

    func markShowUnwatched(_ show: Show) {
        for season in show.seasons {
            for ep in season.episodes {
                watchedStates[AppState.watchKey(showId: show.id, season: season.seasonNumber, episode: ep.episodeNumber)] = false
            }
        }
        guard let session = currentUser else { return }
        PersistenceService.saveWatchedStates(watchedStates, userId: session.userId)
        let states  = watchedStates
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.saveWatchedStates(states, userId: userId, idToken: idToken) }
    }

    func deleteShow(id: String) {
        shows.removeAll { $0.id == id }
        watchedStates = watchedStates.filter { !$0.key.hasPrefix(id + "-") }
        guard let session = currentUser else { return }
        PersistenceService.saveShows(shows, userId: session.userId)
        PersistenceService.saveWatchedStates(watchedStates, userId: session.userId)
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.deleteShow(showId: id, userId: userId, idToken: idToken) }
    }

    // MARK: - TMDB

    @MainActor
    func addShowFromTMDB(searchResult: TMDBSearchResult, service: TMDBService) async throws {
        isAddingShow = true
        defer { isAddingShow = false }
        let detail = try await service.fetchShowDetail(id: searchResult.id)
        let show   = try await service.buildShow(from: detail)
        addShow(show)
    }

    // MARK: - Refresh

    @MainActor
    func refreshAllShows(service: TMDBService, refreshService: RefreshService, isManual: Bool) async {
        guard isLoggedIn else { return }
        if isManual { isRefreshing = true }
        defer { if isManual { isRefreshing = false } }
        let result = await refreshService.refreshStaleShows(in: shows, tmdbService: service, force: isManual)
        applyRefreshResult(result)
    }

    @MainActor
    func applyRefreshResult(_ result: RefreshResult) {
        for updatedShow in result.updatedShows {
            if let idx = shows.firstIndex(where: { $0.id == updatedShow.id }) {
                shows[idx] = updatedShow
            }
        }
        guard !result.updatedShows.isEmpty else { return }
        guard let session = currentUser else { return }
        PersistenceService.saveShows(shows, userId: session.userId)
        let updated = result.updatedShows
        let userId  = session.userId
        let idToken = session.idToken
        Task {
            for show in updated {
                try? await cloudService.saveShow(show, userId: userId, idToken: idToken)
            }
        }
        #if DEBUG
        for (showId, error) in result.errors {
            print("[fynch] Refresh error for \(showId): \(error)")
        }
        #endif
    }
}
