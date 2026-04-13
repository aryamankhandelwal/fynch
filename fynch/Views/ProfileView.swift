import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState

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

                // #if DEBUG
                // if let show = appState.shows.first {
                //     Section("Debug") {
                //         Button("Test Notification (\(show.title))") {
                //             Task {
                //                 await NotificationService.shared.scheduleTestNotification(for: show)
                //             }
                //         }
                //     }
                // }
                // #endif
            }
            .navigationTitle("Bestiary")
            .navigationBarTitleDisplayMode(.inline)
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
