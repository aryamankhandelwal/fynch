import SwiftUI

struct NotificationsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(SocialStore.self) private var socialStore
    @Environment(\.dismiss) private var dismiss

    private var pendingRequests: [FriendRequest] {
        socialStore.friendRequests
            .filter { $0.to == appState.currentUsername }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            Group {
                if pendingRequests.isEmpty {
                    ContentUnavailableView("No Requests", systemImage: "bell.slash")
                } else {
                    List(pendingRequests) { request in
                        requestRow(request)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Friend Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func requestRow(_ request: FriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.from)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("wants to follow you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(relativeTimestamp(request.timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                Button("Accept") {
                    socialStore.acceptFriendRequest(request)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Decline") {
                    socialStore.declineFriendRequest(request)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
