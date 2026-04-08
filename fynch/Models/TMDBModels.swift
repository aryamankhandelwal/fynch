import Foundation

// MARK: - Search

struct TMDBSearchResponse: Decodable {
    let results: [TMDBSearchResult]
}

struct TMDBSearchResult: Decodable, Identifiable {
    let id: Int
    let name: String
    let posterPath: String?
    let genreIds: [Int]
}

// MARK: - Show Detail

struct TMDBShowDetail: Decodable {
    let id: Int
    let name: String
    let numberOfSeasons: Int
    let genres: [TMDBGenre]
}

struct TMDBGenre: Decodable {
    let id: Int
    let name: String
}

// MARK: - Season Detail

struct TMDBSeasonDetail: Decodable {
    let seasonNumber: Int
    let episodes: [TMDBEpisodeDTO]
}

struct TMDBEpisodeDTO: Decodable {
    let id: Int
    let episodeNumber: Int
    let name: String
    let airDate: String?
}
