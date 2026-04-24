import SwiftUI
import Observation

@Observable
final class AppState {
    var shows: [Show] = []
    var watchedStates: [String: Bool] = [:]
    var watchlistedShowIds: Set<String> = []

    var myListShows: [Show]   { shows.filter { !watchlistedShowIds.contains($0.id) } }
    var watchlistShows: [Show] { shows.filter {  watchlistedShowIds.contains($0.id) } }
    var isAddingShow: Bool = false
    var isRefreshing: Bool = false
    var isRestoringSession: Bool = true
    var currentUser: AuthSession? = nil

    var isLoggedIn: Bool { currentUser != nil }

    var pendingDeepLinkShowId: String? = nil

    var currentUsername: String { currentUser?.username ?? "" }

    @ObservationIgnored var socialStore: SocialStore? = nil
    @ObservationIgnored private let authService: AuthService
    @ObservationIgnored private let cloudService: CloudSyncService
    @ObservationIgnored private let notificationService = NotificationService.shared

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
        currentUser        = session
        KeychainService.save(session)
        shows              = PersistenceService.loadShows(userId: session.userId)
        watchedStates      = PersistenceService.loadWatchedStates(userId: session.userId)
        watchlistedShowIds = PersistenceService.loadWatchlistedIds(userId: session.userId)
    }

    /// Fetches fresh data from Firestore and merges into local state.
    @MainActor
    func loadUserData() async {
        guard let session = currentUser else { return }
        do {
            async let cloudShows   = cloudService.loadShows(userId: session.userId, idToken: session.idToken)
            async let cloudStates  = cloudService.loadWatchedStates(userId: session.userId, idToken: session.idToken)
            async let cloudIds     = cloudService.loadWatchlistedIds(userId: session.userId, idToken: session.idToken)
            let (fetchedShows, fetchedStates, fetchedIds) = try await (cloudShows, cloudStates, cloudIds)
            shows              = fetchedShows
            watchedStates      = fetchedStates
            watchlistedShowIds = fetchedIds
            PersistenceService.saveShows(fetchedShows, userId: session.userId)
            PersistenceService.saveWatchedStates(fetchedStates, userId: session.userId)
            PersistenceService.saveWatchlistedIds(fetchedIds, userId: session.userId)
        } catch {
            #if DEBUG
            print("[fynch] loadUserData error: \(error)")
            #endif
        }
    }

    func signOut() {
        shows              = []
        watchedStates      = [:]
        watchlistedShowIds = []
        currentUser        = nil
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

    // Formats today's date as "yyyy-MM-dd" in local timezone for comparison
    private static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func isAired(_ airDate: String?) -> Bool {
        guard let iso = airDate, !iso.isEmpty else { return true }
        // Compare YYYY-MM-DD strings in local timezone so an episode airing
        // "today" (local date) is not treated as aired the evening before.
        let todayString = localDateFormatter.string(from: Date())
        return iso <= todayString
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
                if isNewSeasonUpcoming(for: show) {
                    return "New season upcoming"
                }
                return "Caught up · \(unaired) left in season"
            }
            return "Caught up"
        }
        return remaining == 1 ? "1 new episode" : "\(remaining) new episodes"
    }

    private func isNewSeasonUpcoming(for show: Show) -> Bool {
        guard let nextUnaired = nextUnairedEpisode(for: show),
              let season = show.seasons.first(where: { $0.seasonNumber == nextUnaired.seasonNumber })
        else { return false }
        return !season.episodes.contains(where: { AppState.isAired($0.airDate) })
    }

    func nextAirDateLabel(for show: Show) -> String? {
        guard isCompleted(show),
              let next = nextUnairedEpisode(for: show),
              let airDate = next.airDate else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(identifier: "UTC")
        guard let date = parser.date(from: airDate) else { return nil }
        let fmt = DateFormatter()
        let sameYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
        fmt.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return "Next Airing \(fmt.string(from: date))"
    }

    // MARK: - Calendar

    func allAiringDates() -> Set<String> {
        var result = Set<String>()
        for show in shows {
            for season in show.seasons {
                for episode in season.episodes {
                    if let d = episode.airDate, !d.isEmpty { result.insert(d) }
                }
            }
        }
        return result
    }

    // MARK: - Mutations

    func toggleWatched(showId: String, season: Int, episode: Int) {
        let key = AppState.watchKey(showId: showId, season: season, episode: episode)
        let wasWatched = watchedStates[key] ?? false
        watchedStates[key] = !wasWatched
        guard let session = currentUser else { return }
        PersistenceService.saveWatchedStates(watchedStates, userId: session.userId)
        let states  = watchedStates
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.saveWatchedStates(states, userId: userId, idToken: idToken) }

        // Social feed: log when marking as watched (not unwatching)
        if !wasWatched, let store = socialStore,
           let show = shows.first(where: { $0.id == showId }) {
            logSingleEpisodeWatched(store: store, show: show, seasonNum: season, episodeNum: episode)
        }
    }

    private func logSingleEpisodeWatched(store: SocialStore, show: Show, seasonNum: Int, episodeNum: Int) {
        guard let season = show.seasons.first(where: { $0.seasonNumber == seasonNum }),
              let episode = season.episodes.first(where: { $0.episodeNumber == episodeNum }) else { return }
        let sortedSeasons  = show.seasons.sorted { $0.seasonNumber < $1.seasonNumber }
        let sortedEpisodes = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
        let isFirst = sortedSeasons.first?.seasonNumber == seasonNum &&
                      sortedEpisodes.first?.episodeNumber == episodeNum
        let isLastOfSeason = sortedEpisodes.last?.episodeNumber == episodeNum
        let isLastOfShow   = isLastOfSeason && sortedSeasons.last?.seasonNumber == seasonNum
        store.logWatchedEpisodes(
            username: currentUsername,
            showId: show.id,
            showName: show.title,
            season: seasonNum,
            episode: episodeNum,
            count: 1,
            lastEpisodeTitle: episode.title,
            isFirstEpisodeOfShow: isFirst,
            isLastOfSeason: isLastOfSeason,
            isLastOfShow: isLastOfShow
        )
    }

    func addShow(_ show: Show) {
        guard !shows.contains(where: { $0.id == show.id }) else { return }
        shows.append(show)
        guard let session = currentUser else { return }
        PersistenceService.saveShows(shows, userId: session.userId)
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.saveShow(show, userId: userId, idToken: idToken) }
        let currentShows = shows
        Task { await notificationService.scheduleEpisodeNotifications(for: currentShows) }
    }

    func addToWatchlist(_ show: Show) {
        guard !shows.contains(where: { $0.id == show.id }) else { return }
        shows.append(show)
        watchlistedShowIds.insert(show.id)
        guard let session = currentUser else { return }
        PersistenceService.saveShows(shows, userId: session.userId)
        PersistenceService.saveWatchlistedIds(watchlistedShowIds, userId: session.userId)
        let ids     = watchlistedShowIds
        let userId  = session.userId
        let idToken = session.idToken
        Task {
            try? await cloudService.saveShow(show, userId: userId, idToken: idToken)
            try? await cloudService.saveWatchlistedIds(ids, userId: userId, idToken: idToken)
        }
    }

    func moveToMyList(showId: String) {
        watchlistedShowIds.remove(showId)
        guard let session = currentUser else { return }
        PersistenceService.saveWatchlistedIds(watchlistedShowIds, userId: session.userId)
        let ids     = watchlistedShowIds
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.saveWatchlistedIds(ids, userId: userId, idToken: idToken) }
    }

    func markSeasonWatched(show: Show, season: Season) {
        let prevUnwatched = season.episodes.filter { ep in
            AppState.isAired(ep.airDate) &&
            !(watchedStates[AppState.watchKey(showId: show.id, season: season.seasonNumber, episode: ep.episodeNumber)] ?? false)
        }
        for ep in season.episodes {
            watchedStates[AppState.watchKey(showId: show.id, season: season.seasonNumber, episode: ep.episodeNumber)] = true
        }
        guard let session = currentUser else { return }
        PersistenceService.saveWatchedStates(watchedStates, userId: session.userId)
        let states  = watchedStates
        let userId  = session.userId
        let idToken = session.idToken
        Task { try? await cloudService.saveWatchedStates(states, userId: userId, idToken: idToken) }

        if !prevUnwatched.isEmpty, let store = socialStore {
            let sortedSeasons = show.seasons.sorted { $0.seasonNumber < $1.seasonNumber }
            let isLastOfShow  = sortedSeasons.last?.seasonNumber == season.seasonNumber
            let lastEp = prevUnwatched.sorted { $0.episodeNumber < $1.episodeNumber }.last
            store.logWatchedEpisodes(
                username: currentUsername,
                showId: show.id,
                showName: show.title,
                season: season.seasonNumber,
                episode: nil,
                count: prevUnwatched.count,
                lastEpisodeTitle: lastEp?.title,
                isFirstEpisodeOfShow: false,
                isLastOfSeason: true,
                isLastOfShow: isLastOfShow
            )
        }
    }

    func markSeasonUnwatched(showId: String, season: Season) { // no social logging for unwatching
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
        let prevUnwatchedCount = show.seasons.reduce(0) { total, season in
            total + season.episodes.filter { ep in
                AppState.isAired(ep.airDate) &&
                !(watchedStates[AppState.watchKey(showId: show.id, season: season.seasonNumber, episode: ep.episodeNumber)] ?? false)
            }.count
        }
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

        if prevUnwatchedCount > 0, let store = socialStore {
            let lastSeason = show.seasons.max { $0.seasonNumber < $1.seasonNumber }
            let lastEp     = lastSeason?.episodes.max { $0.episodeNumber < $1.episodeNumber }
            store.logWatchedEpisodes(
                username: currentUsername,
                showId: show.id,
                showName: show.title,
                season: lastSeason?.seasonNumber ?? 1,
                episode: nil,
                count: prevUnwatchedCount,
                lastEpisodeTitle: lastEp?.title,
                isFirstEpisodeOfShow: false,
                isLastOfSeason: true,
                isLastOfShow: true
            )
        }
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
        watchlistedShowIds.remove(id)
        guard let session = currentUser else { return }
        PersistenceService.saveShows(shows, userId: session.userId)
        PersistenceService.saveWatchedStates(watchedStates, userId: session.userId)
        PersistenceService.saveWatchlistedIds(watchlistedShowIds, userId: session.userId)
        let ids     = watchlistedShowIds
        let userId  = session.userId
        let idToken = session.idToken
        Task {
            try? await cloudService.deleteShow(showId: id, userId: userId, idToken: idToken)
            try? await cloudService.saveWatchlistedIds(ids, userId: userId, idToken: idToken)
        }
        let currentShows = shows
        Task {
            await notificationService.cancelNotifications(forShowId: id)
            await notificationService.scheduleEpisodeNotifications(for: currentShows)
        }
    }

    // MARK: - TMDB

    @MainActor
    func addShowFromTMDB(searchResult: TMDBSearchResult, service: TMDBService, destination: AddDestination) async throws {
        isAddingShow = true
        defer { isAddingShow = false }
        let detail = try await service.fetchShowDetail(id: searchResult.id)
        let show   = try await service.buildShow(from: detail)
        switch destination {
        case .myList:    addShow(show)
        case .watchlist: addToWatchlist(show)
        }
    }

    @MainActor
    func addShowsFromTMDB(searchResults: [TMDBSearchResult], service: TMDBService, destination: AddDestination) async throws {
        try await withThrowingTaskGroup(of: Show.self) { group in
            for result in searchResults {
                group.addTask {
                    let detail = try await service.fetchShowDetail(id: result.id)
                    return try await service.buildShow(from: detail)
                }
            }
            for try await show in group {
                switch destination {
                case .myList:    self.addShow(show)
                case .watchlist: self.addToWatchlist(show)
                }
            }
        }
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
        let currentShows = shows
        Task { await notificationService.scheduleEpisodeNotifications(for: currentShows) }
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
