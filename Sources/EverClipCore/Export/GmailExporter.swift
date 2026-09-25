import Foundation

/// Emails the export archive to the user's own Gmail address using the
/// least-privilege `gmail.send` scope. Requires the user's own OAuth client and a
/// recipient address. Off by default.
public final class GmailExporter: ExportTarget {
    public let kind: ExportTargetKind = .gmail
    public var displayName: String { "Gmail" }

    private let auth: GoogleOAuthClient
    private let openURL: (URL) -> Void
    private let recipient: String

    public init(clientID: String, clientSecret: String, recipient: String, openURL: @escaping (URL) -> Void, keychain: KeychainStore = KeychainStore()) {
        self.auth = GoogleOAuthClient(
            clientID: clientID,
            clientSecret: clientSecret,
            scopes: [GoogleOAuthClient.Scopes.gmailSend],
            keychainAccount: "gmail-send-refresh-token",
            keychain: keychain
        )
        self.openURL = openURL
        self.recipient = recipient
    }

    public convenience init?(config: ExportTargetConfig, openURL: @escaping (URL) -> Void, keychain: KeychainStore = KeychainStore()) {
        guard let id = config.googleClientID, !id.isEmpty,
              let secret = config.googleClientSecret, !secret.isEmpty,
              let to = config.gmailRecipient, !to.isEmpty else { return nil }
        self.init(clientID: id, clientSecret: secret, recipient: to, openURL: openURL, keychain: keychain)
    }

    public func export(_ archive: ClipArchive) async throws {
        guard let zipURL = archive.zipURL else {
            throw ExportError.transportFailed("Gmail export needs a zipped archive.")
        }
        let token = try await auth.accessToken(openURL: openURL)
        let data = try Data(contentsOf: zipURL)
        let mime = Self.buildMIME(to: recipient, attachmentName: zipURL.lastPathComponent, zip: data, date: archive.createdAt)
        let raw = GoogleOAuthClient.base64URL(Data(mime.utf8))
        try await send(raw: raw, token: token)
    }

    private func send(raw: String, token: String) async throws {
        let payload = try JSONSerialization.data(withJSONObject: ["raw": raw])
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: respData, encoding: .utf8) ?? ""
            throw ExportError.transportFailed("Gmail send failed: \(text)")
        }
    }

    /// Builds an RFC 2822 multipart message with the zip attached. Exposed for tests.
    static func buildMIME(to: String, attachmentName: String, zip: Data, date: Date) -> String {
        let boundary = "everclip-mime-boundary"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let dateHeader = formatter.string(from: date)
        let base64 = zip.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn])

        return """
        To: \(to)\r
        Subject: EverClip clipboard backup\r
        Date: \(dateHeader)\r
        MIME-Version: 1.0\r
        Content-Type: multipart/mixed; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: text/plain; charset="UTF-8"\r
        \r
        Your EverClip clipboard history backup is attached.\r
        \r
        --\(boundary)\r
        Content-Type: application/zip; name="\(attachmentName)"\r
        Content-Disposition: attachment; filename="\(attachmentName)"\r
        Content-Transfer-Encoding: base64\r
        \r
        \(base64)\r
        --\(boundary)--\r

        """
    }
}
