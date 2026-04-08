import Foundation

struct AuthSession: Codable {
    let userId: String
    let username: String
    var idToken: String
    var refreshToken: String
    var idTokenExpiry: Date
}
