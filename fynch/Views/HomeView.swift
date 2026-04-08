import SwiftUI

enum ShowSortOrder: String, CaseIterable {
    case `default` = "Default"
    case alphabetical = "A → Z"
    case mostToWatch = "Most to watch"
    case caughtUpLast = "Caught up last"
}

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddSheet = false
    @State private var sortOrder: ShowSortOrder = .default

    private var sortedShows: [Show] {
        switch sortOrder {
        case .default:
            return appState.shows
        case .alphabetical:
            return appState.shows.sorted { $0.title < $1.title }
        case .mostToWatch:
            return appState.shows.sorted {
                appState.episodesRemaining(for: $0) > appState.episodesRemaining(for: $1)
            }
        case .caughtUpLast:
            return appState.shows.sorted {
                let lhsDone = appState.isCompleted($0)
                let rhsDone = appState.isCompleted($1)
                if lhsDone == rhsDone { return false }
                return !lhsDone
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedShows) { show in
                    NavigationLink(value: show) {
                        ShowRowView(
                            show: show,
                            isCompleted: appState.isCompleted(show),
                            statusLabel: appState.statusLabel(for: show)
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            appState.deleteShow(id: show.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("fynch")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Show.self) { show in
                ShowDetailView(show: show)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Section("Sort by") {
                            ForEach(ShowSortOrder.allCases, id: \.self) { order in
                                Button {
                                    withAnimation { sortOrder = order }
                                } label: {
                                    HStack {
                                        Text(order.rawValue)
                                        if sortOrder == order {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddShowView()
            }
            .animation(.easeInOut, value: appState.shows.map(\.id))
        }
    }
}
