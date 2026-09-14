import Foundation
import Security
import AuthenticationServices
import CryptoKit

// MARK: - Keychain Protocol & Implementation

public protocol KeychainManaging: Sendable {
    func save(key: String, data: Data) throws
    func read(key: String) -> Data?
    func delete(key: String) throws
}

public final class KeychainStorage: KeychainManaging, Sendable {
    private let service: String

    public init(service: String = "com.kiclient.app") {
        self.service = service
    }

    public func save(key: String, data: Data) throws {
        // Varsa önce sil
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain kayıt hatası: \(status)"])
        }
    }

    public func read(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }

    public func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// In-Memory Keychain for unit tests
public final class InMemoryKeychainStorage: KeychainManaging, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(key: String, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = data
    }

    public func read(key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func delete(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}

// MARK: - OAuth Token Models

public struct OAuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String
    public let expiresIn: Int
    public let scope: String?
    public let issuedAt: Date

    public init(accessToken: String, refreshToken: String?, tokenType: String, expiresIn: Int, scope: String?, issuedAt: Date = Date()) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
        self.issuedAt = issuedAt
    }

    public var isExpired: Bool {
        // 60 saniyelik güvenlik marjı
        return Date().timeIntervalSince(issuedAt) >= Double(expiresIn - 60)
    }
}

// MARK: - KickAuthManager

public protocol AuthManaging: AnyObject, Sendable {
    var isAuthenticated: Bool { get }
    var currentTokens: OAuthTokens? { get }
    func getValidAccessToken() async throws -> String
    func logout()
}

public final class KickAuthManager: NSObject, AuthManaging, ObservableObject, @unchecked Sendable {
    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var currentTokens: OAuthTokens?
    @Published public var authErrorMessage: String?

    public var clientId: String {
        get {
            UserDefaults.standard.string(forKey: "kick_oauth_client_id") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kick_oauth_client_id")
        }
    }

    public var redirectURI: String {
        get {
            UserDefaults.standard.string(forKey: "kick_oauth_redirect_uri") ?? "kiclient://oauth-callback"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kick_oauth_redirect_uri")
        }
    }

    private let keychain: KeychainManaging
    private let tokenKey = "kick_oauth_tokens"
    private let session: URLSession
    private var authSession: ASWebAuthenticationSession?

    public init(
        keychain: KeychainManaging = KeychainStorage(),
        session: URLSession = .shared
    ) {
        self.keychain = keychain
        self.session = session
        super.init()
        loadStoredTokens()
    }

    private func loadStoredTokens() {
        if let data = keychain.read(key: tokenKey),
           let tokens = try? JSONDecoder().decode(OAuthTokens.self, from: data) {
            self.currentTokens = tokens
            self.isAuthenticated = true
        } else {
            self.currentTokens = nil
            self.isAuthenticated = false
        }
    }

    // MARK: - PKCE Utilities

    public static func generatePKCEVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    public static func generatePKCEChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .ascii) else { return "" }
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    // MARK: - Login Flow

    @MainActor
    public func startLogin() async throws {
        guard !clientId.isEmpty else {
            authErrorMessage = "Lütfen Ayarlar'dan Kick Client ID tanımlayın."
            throw NSError(domain: "KickAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Client ID eksik"])
        }

        let verifier = Self.generatePKCEVerifier()
        let challenge = Self.generatePKCEChallenge(from: verifier)

        var components = URLComponents(string: "https://id.kick.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "chat:write user:read channel:read"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else {
            throw NSError(domain: "KickAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz yetki URL'si"])
        }

        let callbackScheme = URL(string: redirectURI)?.scheme ?? "kiclient"

        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL = callbackURL,
                      let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: NSError(domain: "KickAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Yetki kodu alınamadı"]))
                    return
                }
                continuation.resume(returning: code)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }

        // Token takası
        try await exchangeCodeForTokens(code: code, verifier: verifier)
    }

    public func exchangeCodeForTokens(code: String, verifier: String) async throws {
        guard let tokenURL = URL(string: "https://id.kick.com/oauth/token") else { return }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
            "code": code
        ]

        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Bilinmeyen hata"
            throw NSError(domain: "KickAuth", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "Token alınamadı: \(errorText)"])
        }

        let decoded = try JSONDecoder().decode(TokenResponseJSON.self, from: data)
        let tokens = OAuthTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            tokenType: decoded.token_type ?? "Bearer",
            expiresIn: decoded.expires_in ?? 3600,
            scope: decoded.scope
        )

        try saveTokens(tokens)
    }

    public func getValidAccessToken() async throws -> String {
        guard let tokens = currentTokens else {
            throw NSError(domain: "KickAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Kullanıcı girişi yapılmamış."])
        }

        if !tokens.isExpired {
            return tokens.accessToken
        }

        // Token süresi dolmuş, refresh_token ile yenile
        guard let refreshToken = tokens.refreshToken else {
            logout()
            throw NSError(domain: "KickAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Token süresi doldu ve yenileme anahtarı yok. Lütfen tekrar giriş yapın."])
        }

        return try await refreshAccessToken(refreshToken: refreshToken)
    }

    public func refreshAccessToken(refreshToken: String) async throws -> String {
        guard let tokenURL = URL(string: "https://id.kick.com/oauth/token") else {
            throw NSError(domain: "KickAuth", code: 400, userInfo: nil)
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "refresh_token",
            "client_id": clientId,
            "refresh_token": refreshToken
        ]

        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            logout()
            throw NSError(domain: "KickAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Token yenilenemedi, lütfen tekrar giriş yapın."])
        }

        let decoded = try JSONDecoder().decode(TokenResponseJSON.self, from: data)
        let tokens = OAuthTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? refreshToken,
            tokenType: decoded.token_type ?? "Bearer",
            expiresIn: decoded.expires_in ?? 3600,
            scope: decoded.scope
        )

        try saveTokens(tokens)
        return tokens.accessToken
    }

    public func saveTokens(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try keychain.save(key: tokenKey, data: data)
        DispatchQueue.main.async {
            self.currentTokens = tokens
            self.isAuthenticated = true
            self.authErrorMessage = nil
        }
    }

    public func logout() {
        try? keychain.delete(key: tokenKey)
        DispatchQueue.main.async {
            self.currentTokens = nil
            self.isAuthenticated = false
        }
    }
}

extension KickAuthManager: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

private struct TokenResponseJSON: Codable {
    let access_token: String
    let refresh_token: String?
    let token_type: String?
    let expires_in: Int?
    let scope: String?
}
