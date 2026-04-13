import SwiftUI

struct WatchlistView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddSheet = false
    @State private var showToMove: Show? = nil
    @State private var searchText = ""

    let tmdbService: TMDBService

    var body: some View {
        NavigationStack {
            Group {
                let filteredShows = searchText.isEmpty
                    ? appState.watchlistShows
                    : appState.watchlistShows.filter { $0.title.localizedCaseInsensitiveContains(searchText) }

                if appState.watchlistShows.isEmpty {
                    ContentUnavailableView(
                        "Nothing queued",
                        systemImage: "bookmark",
                        description: Text("Tap + to add shows you plan to watch.")
                    )
                } else {
                    List {
                        ForEach(filteredShows) { show in
                            Button {
                                showToMove = show
                            } label: {
                                WatchlistRowView(
                                    show: show,
                                    unwatchedCount: appState.episodesRemaining(for: show)
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.deleteShow(id: show.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Watchlist")
            .sheet(isPresented: $showingAddSheet) {
                AddShowView(tmdbService: tmdbService, destination: .watchlist)
            }
            .alert(
                "Move to My List?",
                isPresented: Binding(
                    get: { showToMove != nil },
                    set: { if !$0 { showToMove = nil } }
                ),
                presenting: showToMove
            ) { show in
                Button("Move") {
                    appState.moveToMyList(showId: show.id)
                    showToMove = nil
                }
                Button("Cancel", role: .cancel) {
                    showToMove = nil
                }
            } message: { show in
                Text("\u{201C}\(show.title)\u{201D} will move to My List.")
            }
        }
    }
}
