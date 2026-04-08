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
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func profileRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
