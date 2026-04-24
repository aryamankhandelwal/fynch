import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(SocialStore.self) private var socialStore
    @State private var showClearFeedConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    profileRow(label: "Username", value: appState.currentUser?.username ?? "—")
                }

                Section {
                    Button("Log Out", role: .destructive) {
                        appState.signOut()
                    }
                }

                if appState.currentUsername == "arya" {
                    Section {
                        Button(role: .destructive) {
                            showClearFeedConfirmation = true
                        } label: {
                            Label("Clear Feed", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Bestiary")
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog(
            "Clear All Feed Activity",
            isPresented: $showClearFeedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                socialStore.clearAllFeeds()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all feed activity for every user. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func profileRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.msBody)
            Spacer()
            Text(value).font(.msBody).foregroundStyle(.secondary)
        }
    }
}
