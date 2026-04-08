import Foundation

// MARK: - Error

enum TMDBError: Error, LocalizedError {
    case unauthorized
    case notFound
    case serverError(Int)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:          return "Invalid TMDB API token."
        case .notFound:              return "Show not found."
        case .serverError(let code): return "Server error (\(code))."
        case .decodingFailed(let e): return "Data error: \(e.localizedDescription)"
        }
    }
}

// MARK: - Service

actor TMDBService {
    private let bearerToken: String
    private let session: URLSession
    private let baseURL = URL(string: "https://api.themoviedb.org/3")!

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(bearerToken: String, session: URLSession = .shared) {
        self.bearerToken = bearerToken
        self.session = session
    }

    // MARK: - Public API

    func searchShows(query: String) async throws -> [TMDBSearchResult] {
        let response: TMDBSearchResponse = try await request(
            path: "/search/tv",
            queryItems: [URLQueryItem(name: "query", value: query)]
        )
        return response.results
    }

    func fetchShowDetail(id: Int) async throws -> TMDBShowDetail {
        try await request(path: "/tv/\(id)")
    }

    func fetchSeason(showId: Int, seasonNumber: Int) async throws -> TMDBSeasonDetail {
        try await request(path: "/tv/\(showId)/season/\(seasonNumber)")
    }

    /// Fetches all seasons concurrently and assembles a fully populated Show.
    func buildShow(from showDetail: TMDBShowDetail) async throws -> Show {
        let seasonCount = max(1, showDetail.numberOfSeasons)

        let seasons: [Season] = try await withThrowingTaskGroup(of: Season?.self) { group in
            for n in 1...seasonCount {
                group.addTask {
                    let seasonData = try await self.fetchSeason(showId: showDetail.id, seasonNumber: n)
                    guard seasonData.seasonNumber > 0 else { return nil }
                    let episodes = seasonData.episodes.map { ep in
                        Episode(
                            id: "tmdb-\(showDetail.id)-s\(n)e\(ep.episodeNumber)",
                            seasonNumber: n,
                            episodeNumber: ep.episodeNumber,
                            title: ep.name,
                            airDate: ep.airDate
                        )
                    }.sorted { $0.episodeNumber < $1.episodeNumber }
                    return Season(
                        id: "tmdb-\(showDetail.id)-s\(n)",
                        seasonNumber: n,
                        episodes: episodes
                    )
                }
            }
            var result: [Season] = []
            for try await season in group {
                if let season { result.append(season) }
            }
            return result.sorted { $0.seasonNumber < $1.seasonNumber }
        }

        let colorIndex = showDetail.id % Show.palette.count
        return Show(
            id: "tmdb-\(showDetail.id)",
            tmdbId: showDetail.id,
            title: showDetail.name,
            posterColor: Show.palette[colorIndex],
            colorIndex: colorIndex,
            genres: showDetail.genres.map(\.name),
            seasons: seasons
        )
    }

    // MARK: - Private

    private func request<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw TMDBError.serverError(0)
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw TMDBError.decodingFailed(error)
            }
        case 401:
            throw TMDBError.unauthorized
        case 404:
            throw TMDBError.notFound
        default:
            throw TMDBError.serverError(http.statusCode)
        }
    }
}
