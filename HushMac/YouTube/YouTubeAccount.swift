import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import WebKit

/// The two halves of connecting YouTube:
/// 1. A YouTube sign-in inside Hush's web view (Google's own page), so the player plays as you —
///    with your Premium, no ads. The session lives in WebKit's persistent store and survives
///    relaunch.
/// 2. A read-only Google approval for YouTube's official Data API, so Hush can list your
///    subscriptions and playlists. You create the OAuth client ID once (in your own Google Cloud
///    project) and paste it into Hush; the access is kept in the Keychain.
/// Hush never sees your password and never reads or stores your cookies.
@MainActor
@Observable
final class YouTubeAccount: NSObject {
    static let shared = YouTubeAccount()

    static let signInURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/")!
    private static let clientIDKey = "hush.youtube.clientID"
    private static let scope = "https://www.googleapis.com/auth/youtube.readonly"

    /// Signed in on the web side (nil until checked).
    private(set) var isWebSignedIn: Bool?
    /// The OAuth client ID you created and pasted in.
    private(set) var clientID: String?
    /// Whether Hush may call the Data API (an approval is in the Keychain).
    private(set) var isAuthorized = false
    private(set) var authError: String?

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessTokenExpiry = Date.distantPast
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private var checker: WKWebView?
    @ObservationIgnored private var checkContinuation: CheckedContinuation<Bool, Never>?

    override private init() {
        clientID = UserDefaults.standard.string(forKey: Self.clientIDKey)
        super.init()
        isAuthorized = Keychain.read() != nil
    }

    var isConnected: Bool { isWebSignedIn == true && isAuthorized }

    /// The web view configuration every YouTube page in Hush uses (the persistent store that holds
    /// your sign-in).
    static func webConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        return configuration
    }

    // MARK: Web sign-in

    /// Asks youtube.com itself whether you're signed in (its own `LOGGED_IN` flag), in a hidden web view.
    func refreshWebSignIn() async {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: Self.webConfiguration())
        view.navigationDelegate = self
        checker = view
        let signedIn = await withCheckedContinuation { continuation in
            checkContinuation = continuation
            view.load(URLRequest(url: URL(string: "https://www.youtube.com/")!))
        }
        checker = nil
        isWebSignedIn = signedIn
    }

    fileprivate func checkerFinished(_ view: WKWebView) {
        view.evaluateJavaScript("!!(window.ytcfg && ytcfg.get('LOGGED_IN'))") { [weak self] result, _ in
            Task { @MainActor in
                self?.checkContinuation?.resume(returning: (result as? Bool) ?? false)
                self?.checkContinuation = nil
            }
        }
    }

    fileprivate func checkerFailed() {
        checkContinuation?.resume(returning: isWebSignedIn ?? false)
        checkContinuation = nil
    }

    func webSignInFinished() {
        Task { await refreshWebSignIn() }
    }

    /// Signs out of YouTube on both halves: the web session (Google and YouTube data in Hush's
    /// web store) and the Data API approval.
    func signOut() async {
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let google = records.filter { record in
            ["youtube", "google", "gstatic", "ytimg"].contains { record.displayName.contains($0) }
        }
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: google)
        Keychain.delete()
        accessToken = nil
        isAuthorized = false
        isWebSignedIn = false
    }

    // MARK: Data API approval (OAuth with PKCE, Google's flow for installed apps)

    func setClientID(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        clientID = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(clientID, forKey: Self.clientIDKey)
        authError = nil
    }

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc" (Google's
    /// redirect scheme for iOS/macOS clients).
    private var redirectScheme: String? {
        guard let clientID, clientID.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    func authorize() {
        guard let clientID, let scheme = redirectScheme else {
            authError = "That doesn't look like an OAuth client ID (it should end in .apps.googleusercontent.com)."
            return
        }
        authError = nil
        let verifier = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let redirect = "\(scheme):/oauth2redirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: scheme) { [weak self] callback, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    if (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.authError = error.localizedDescription
                    }
                    return
                }
                guard let callback,
                      let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.authError = "Google didn't send an approval back."
                    return
                }
                await self.exchange(code: code, verifier: verifier, redirect: redirect, clientID: clientID)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    private func exchange(code: String, verifier: String, redirect: String, clientID: String) async {
        let body = [
            "code": code, "client_id": clientID, "redirect_uri": redirect,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ]
        guard let token: TokenResponse = await Self.postForm("https://oauth2.googleapis.com/token", body) else {
            authError = "Google didn't accept the approval. Check the client ID and that you're a test user."
            return
        }
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(token.expires_in - 60)
        if let refresh = token.refresh_token { Keychain.save(refresh) }
        isAuthorized = true
    }

    /// A valid access token, refreshed from the Keychain's refresh token when needed.
    func validAccessToken() async -> String? {
        if let accessToken, Date() < accessTokenExpiry { return accessToken }
        guard let clientID, let refresh = Keychain.read() else { return nil }
        let body = ["client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token"]
        guard let token: TokenResponse = await Self.postForm("https://oauth2.googleapis.com/token", body) else {
            // The approval was withdrawn (or the client deleted): ask again.
            Keychain.delete()
            isAuthorized = false
            return nil
        }
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(token.expires_in - 60)
        return token.access_token
    }

    private static func postForm<T: Decodable>(_ address: String, _ fields: [String: String]) async -> T? {
        var request = URLRequest(url: URL(string: address)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

extension YouTubeAccount: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.checkerFinished(webView) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.checkerFailed() }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.checkerFailed() }
    }
}

extension YouTubeAccount: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The Data API refresh token, in the Keychain (never in files or defaults).
private enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hush.player.mac.youtube",
        kSecAttrAccount as String: "youtube-readonly",
    ]

    static func save(_ token: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
