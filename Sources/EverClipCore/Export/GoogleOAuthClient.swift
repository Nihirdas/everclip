import Foundation
import CryptoKit
import Network

/// OAuth 2.0 for installed apps, using the loopback-IP redirect and PKCE, per
/// Google's documented desktop-app flow.
///
/// The caller supplies its own OAuth client (client id/secret) — nothing is
/// bundled — and an `openURL` closure so the app layer can open the consent page.
/// Refresh tokens are stored in the Keychain; only short-lived access tokens are
/// kept in memory. This path is opt-in and unused unless the user configures it.
public final class GoogleOAuthClient {
    public struct Scopes {
        public static let driveFile = "https://www.googleapis.com/auth/drive.file"
        public static let gmailSend = "https://www.googleapis.com/auth/gmail.send"
    }

    private let clientID: String
    private let clientSecret: String
    private let scopes: [String]
    private let keychain: KeychainStore
    private let keychainAccount: String

    private let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    private var cachedAccessToken: String?
    private var cachedExpiry: Date?

    public init(clientID: String, clientSecret: String, scopes: [String], keychainAccount: String, keychain: KeychainStore = KeychainStore()) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.scopes = scopes
        self.keychain = keychain
        self.keychainAccount = keychainAccount
    }

    public var hasStoredAuthorization: Bool {
        keychain.get(account: keychainAccount) != nil
    }

    public func signOut() {
        keychain.delete(account: keychainAccount)
        cachedAccessToken = nil
        cachedExpiry = nil
    }

    /// Returns a valid access token, refreshing or running the interactive flow as needed.
    public func accessToken(openURL: @escaping (URL) -> Void) async throws -> String {
        if let token = cachedAccessToken, let expiry = cachedExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        if let refreshToken = keychain.get(account: keychainAccount) {
            do {
                return try await refresh(using: refreshToken)
            } catch {
                // Refresh token revoked/expired — fall through to interactive.
            }
        }
        return try await interactiveAuthorize(openURL: openURL)
    }

    // MARK: - Interactive authorization

    private func interactiveAuthorize(openURL: @escaping (URL) -> Void) async throws -> String {
        let verifier = Self.randomURLSafe(byteCount: 48)
        let challenge = Self.codeChallenge(for: verifier)

        let receiver = LoopbackReceiver()
        let port = try receiver.start()
        let redirectURI = "http://127.0.0.1:\(port)"

        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else {
            receiver.stop()
            throw ExportError.authFailed("Could not build the authorization URL.")
        }

        openURL(authURL)

        let code: String
        do {
            code = try await receiver.waitForCode(timeout: 300)
        } catch {
            receiver.stop()
            throw ExportError.authFailed("Did not receive an authorization code: \(error.localizedDescription)")
        }
        receiver.stop()

        let tokens = try await exchange(code: code, verifier: verifier, redirectURI: redirectURI)
        if let refresh = tokens.refreshToken {
            keychain.set(refresh, account: keychainAccount)
        }
        cachedAccessToken = tokens.accessToken
        cachedExpiry = Date().addingTimeInterval(tokens.expiresIn)
        return tokens.accessToken
    }

    // MARK: - Token requests

    private struct TokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
    }

    private func exchange(code: String, verifier: String, redirectURI: String) async throws -> TokenResponse {
        let form = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        return try await postToken(form)
    }

    private func refresh(using refreshToken: String) async throws -> String {
        let form = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        let tokens = try await postToken(form)
        cachedAccessToken = tokens.accessToken
        cachedExpiry = Date().addingTimeInterval(tokens.expiresIn)
        return tokens.accessToken
    }

    private func postToken(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(form).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ExportError.authFailed("Token request failed: \(body)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw ExportError.authFailed("Malformed token response.")
        }
        let expiresIn = (json["expires_in"] as? TimeInterval) ?? 3600
        let refreshToken = json["refresh_token"] as? String
        return TokenResponse(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
    }

    // MARK: - Helpers

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
