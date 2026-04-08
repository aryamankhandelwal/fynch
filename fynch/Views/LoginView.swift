import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var username  = ""
    @State private var password  = ""
    @State private var showError = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("fynch")
                .font(.system(size: 48, weight: .bold, design: .default))
                .foregroundStyle(.primary)

            Spacer().frame(height: 16)

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if showError {
                Text("Incorrect username or password.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            Button {
                guard !isLoading else { return }
                isLoading = true
                showError = false
                Task {
                    do {
                        try await appState.signIn(username: username, password: password)
                    } catch {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showError = true
                        }
                    }
                    isLoading = false
                }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign In")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isLoading || username.isEmpty || password.isEmpty)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
