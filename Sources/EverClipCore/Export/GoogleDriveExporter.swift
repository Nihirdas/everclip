import Foundation

/// Uploads the export archive (a single zip) to the user's own Google Drive using
/// the least-privilege `drive.file` scope, so EverClip can only see files it created.
///
/// Requires the user's own OAuth client (configured in Settings). Off by default.
public final class GoogleDriveExporter: ExportTarget {
    public let kind: ExportTargetKind = .googleDrive
    public var displayName: String { "Google Drive" }

    private let auth: GoogleOAuthClient
    private let openURL: (URL) -> Void

    public init(clientID: String, clientSecret: String, openURL: @escaping (URL) -> Void, keychain: KeychainStore = KeychainStore()) {
        self.auth = GoogleOAuthClient(
            clientID: clientID,
            clientSecret: clientSecret,
            scopes: [GoogleOAuthClient.Scopes.driveFile],
            keychainAccount: "google-drive-refresh-token",
            keychain: keychain
        )
        self.openURL = openURL
    }

    public convenience init?(config: ExportTargetConfig, openURL: @escaping (URL) -> Void, keychain: KeychainStore = KeychainStore()) {
        guard let id = config.googleClientID, !id.isEmpty,
              let secret = config.googleClientSecret, !secret.isEmpty else { return nil }
        self.init(clientID: id, clientSecret: secret, openURL: openURL, keychain: keychain)
    }

    public func export(_ archive: ClipArchive) async throws {
        guard let zipURL = archive.zipURL else {
            throw ExportError.transportFailed("Google Drive export needs a zipped archive.")
        }
        let token = try await auth.accessToken(openURL: openURL)
        let data = try Data(contentsOf: zipURL)
        try await upload(name: zipURL.lastPathComponent, zip: data, token: token)
    }

    private func upload(name: String, zip: Data, token: String) async throws {
        let boundary = "everclip-\(UUID().uuidString)"
        let metadata = try JSONSerialization.data(withJSONObject: ["name": name])

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metadata)
        append("\r\n--\(boundary)\r\n")
        append("Content-Type: application/zip\r\n\r\n")
        body.append(zip)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: respData, encoding: .utf8) ?? ""
            throw ExportError.transportFailed("Drive upload failed: \(text)")
        }
    }
}
