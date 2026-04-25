import SwiftUI

struct CombinedFeedView: View {
    @Environment(AppState.self) private var appState
    @Environment(SocialStore.self) private var socialStore
    @State private var searchText = ""
    @State private var searchResults: [UserProfile] = []
    @State private var isSearching = false
    @State private var showNotifications = false

    private var currentUsername: String { appState.currentUsername }

    // Pending friend requests count drives the bell badge
    private var pendingRequestCount: Int {
        socialStore.friendRequests.filter { $0.to == currentUsername }.count
    }

    // Feed events visible to this user (self + friends), newest first
    private var visibleEvents: [FeedEvent] {
        let friendList = socialStore.friends[currentUsername] ?? []
        let visibleUsers = Set([currentUsername] + friendList)
        return socialStore.feedEvents
            .filter { visibleUsers.contains($0.username) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // Group consecutive same-user events within 5 minutes into display sessions.
    // Returns (primary event, additionalShowCount) pairs.
    private var displayableEvents: [(event: FeedEvent, additionalShowCount: Int)] {
        var result: [(event: FeedEvent, additionalShowCount: Int)] = []
        var processed = Set<UUID>()

        for event in visibleEvents {
            guard !processed.contains(event.id) else { continue }

            let sessionEvents = visibleEvents.filter { other in
                !processed.contains(other.id) &&
                other.username == event.username &&
                abs(other.timestamp.timeIntervalSince(event.timestamp)) < 300
            }
            sessionEvents.forEach { processed.insert($0.id) }

            let distinctShows = Set(sessionEvents.map { $0.showName })
            let additionalShowCount = max(0, distinctShows.count - 1)
            result.append((event: event, additionalShowCount: additionalShowCount))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    feedContent
                } else {
                    searchContent
                }
            }
            .navigationTitle("Bestiary")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "search friends"
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NotificationBadgeView(unreadCount: pendingRequestCount) {
                        showNotifications = true
                    }
                }
            }
        }
        .textInputAutocapitalization(.never)
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet()
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                searchResults = []
                isSearching = false
            } else {
                Task { await performSearch(query: newValue) }
            }
        }
        .task {
            await socialStore.loadFromFirestore()
        }
    }

    // MARK: - Feed content

    @ViewBuilder
    private var feedContent: some View {
        if displayableEvents.isEmpty {
            ContentUnavailableView(
                "Nothing yet",
                systemImage: "person.2",
                description: Text("Watch some episodes or add friends to see activity here.")
            )
        } else {
            List {
                ForEach(displayableEvents, id: \.event.id) { item in
                    FeedRowView(event: item.event, additionalShowCount: item.additionalShowCount)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await socialStore.loadFromFirestore()
            }
        }
    }

    // MARK: - Search content

    @ViewBuilder
    private var searchContent: some View {
        if isSearching {
            ProgressView()
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty {
            ContentUnavailableView(
                "No users found",
                systemImage: "person.slash",
                description: Text("Try a different username.")
            )
        } else {
            List {
                ForEach(searchResults, id: \.username) { profile in
                    searchResultRow(profile)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Helpers

    @MainActor
    private func performSearch(query: String) async {
        isSearching = true
        searchResults = await socialStore.searchUsers(prefix: query)
        isSearching = false
    }

    @ViewBuilder
    private func searchResultRow(_ profile: UserProfile) -> some View {
        HStack {
            Text(profile.username)
                .font(.subheadline)
            Spacer()
            if socialStore.areFriends(currentUsername, profile.username) {
                Text("Friends")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if socialStore.hasPendingRequest(from: currentUsername, to: profile.username) {
                Text("Pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Add") {
                    socialStore.sendFriendRequest(
                        to: profile.username,
                        recipientUserId: profile.userId
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
