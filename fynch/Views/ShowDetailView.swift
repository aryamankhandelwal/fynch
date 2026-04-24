import SwiftUI

struct ShowDetailView: View {
    let show: Show
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var expandedFutureSeasons: Set<Int> = []

    var body: some View {
        let nextUnairedId = appState.nextUnairedEpisode(for: show)?.id
        let allShowWatched = appState.isShowFullyWatched(show)

        List {
            ForEach(show.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber })) { season in
                let sortedEpisodes = season.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber })
                let aired   = sortedEpisodes.filter {  AppState.isAired($0.airDate) }
                let unaired = sortedEpisodes.filter { !AppState.isAired($0.airDate) }

                Section {
                    // Aired episodes
                    ForEach(aired) { episode in
                        EpisodeRowView(
                            episode: episode,
                            isWatched: appState.isWatched(
                                showId: show.id,
                                season: season.seasonNumber,
                                episode: episode.episodeNumber
                            ),
                            isNext: appState.nextEpisode(for: show)?.id == episode.id,
                            isNextUnaired: false,
                            onTap: {
                                appState.toggleWatched(
                                    showId: show.id,
                                    season: season.seasonNumber,
                                    episode: episode.episodeNumber
                                )
                            }
                        )
                    }

                    // Unaired episodes — first always visible, rest collapsed
                    if let first = unaired.first {
                        EpisodeRowView(
                            episode: first,
                            isWatched: false,
                            isNext: false,
                            isNextUnaired: first.id == nextUnairedId && appState.isCompleted(show),
                            onTap: {}
                        )

                        if unaired.count > 1 {
                            if expandedFutureSeasons.contains(season.seasonNumber) {
                                ForEach(unaired.dropFirst()) { episode in
                                    EpisodeRowView(
                                        episode: episode,
                                        isWatched: false,
                                        isNext: false,
                                        isNextUnaired: false,
                                        onTap: {}
                                    )
                                }
                            } else {
                                let remaining = unaired.count - 1
                                Button {
                                    expandedFutureSeasons.insert(season.seasonNumber)
                                } label: {
                                    HStack {
                                        Text("\(remaining) more episode\(remaining == 1 ? "" : "s")")
                                            .font(.subheadline)
                                            .foregroundStyle(.blue)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .foregroundStyle(.blue)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Season \(season.seasonNumber)")
                        Spacer()
                        let allWatched = appState.isSeasonWatched(showId: show.id, season: season)
                        Button(allWatched ? "Deselect All" : "Select All") {
                            if allWatched {
                                appState.markSeasonUnwatched(showId: show.id, season: season)
                            } else {
                                appState.markSeasonWatched(show: show, season: season)
                            }
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                }
            }
        }
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(allShowWatched ? "Deselect All" : "Select All") {
                    if allShowWatched {
                        appState.markShowUnwatched(show)
                    } else {
                        appState.markShowWatched(show)
                    }
                }
                .font(.caption)
            }
        }
    }
}
