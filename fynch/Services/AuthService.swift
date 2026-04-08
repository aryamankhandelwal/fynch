import Foundation

enum AuthError: LocalizedError {
    case invalidCredentials
    case networkError(Error)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:    return "Incorrect username or password."
        case .networkError:          return "Network error. Please try again."
        case .serverError(let code): return "Server error (\(code)). Please try again."
        }
    }
}

actor AuthService {
    private let apiKey = FirebaseConfig.apiKey

    /// Signs in with a username (converted to a synthetic email internally).
    func signIn(username: String, password: String) async throws -> AuthSession {
        let email = "\(username)@fynch.app"
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(apiKey)")!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse

        if http.statusCode == 400 { throw AuthError.invalidCredentials }
        guard http.statusCode == 200 else { throw AuthError.serverError(http.statusCode) }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return AuthSession(
            userId:        json["localId"]      as! String,
            username:      username,
            idToken:       json["idToken"]      as! String,
            refreshToken:  json["refreshToken"] as! String,
            idTokenExpiry: Date(timeIntervalSinceNow: Double(json["expiresIn"] as! String) ?? 3600)
        )
    }

    /// Refreshes the idToken if it expires within 5 minutes; otherwise returns the session unchanged.
    func refreshIfNeeded(_ session: AuthSession) async throws -> AuthSession {
        guard session.idTokenExpiry.timeIntervalSinceNow < 300 else { return session }

        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&refresh_token=\(session.refreshToken)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        guard http.statusCode == 200 else { throw AuthError.serverError(http.statusCode) }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var updated = session
        updated.idToken       = json["id_token"]      as! String
        updated.refreshToken  = json["refresh_token"] as! String
        updated.idTokenExpiry = Date(timeIntervalSinceNow: Double(json["expires_in"] as! String) ?? 3600)
        return updated
    }
}
