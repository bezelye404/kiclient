import Foundation

public protocol ChatSending: Sendable {
    func sendMessage(content: String, broadcasterUserId: Int) async throws
}

public enum ChatSendError: LocalizedError, Equatable {
    case emptyMessage
    case unauthorized
    case rateLimited
    case serverError(Int, String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Boş mesaj gönderilemez."
        case .unauthorized:
            return "Yetkilendirme hatası. Lütfen tekrar giriş yapın."
        case .rateLimited:
            return "Çok hızlı mesaj gönderiyorsunuz. Lütfen biraz bekleyin."
        case .serverError(let code, let msg):
            return "Kick sunucu hatası (\(code)): \(msg)"
        case .networkError(let msg):
            return "Bağlantı hatası: \(msg)"
        }
    }
}

public final class KickChatSender: ChatSending, @unchecked Sendable {
    private let authManager: AuthManaging
    private let session: URLSession

    public init(
        authManager: AuthManaging,
        session: URLSession = .shared
    ) {
        self.authManager = authManager
        self.session = session
    }

    public func sendMessage(content: String, broadcasterUserId: Int) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ChatSendError.emptyMessage
        }

        let token: String
        do {
            token = try await authManager.getValidAccessToken()
        } catch {
            throw ChatSendError.unauthorized
        }

        guard let url = URL(string: "https://api.kick.com/public/v1/chat") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let payload: [String: Any] = [
            "content": trimmed,
            "type": "user",
            "broadcaster_user_id": broadcasterUserId
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = httpBody

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ChatSendError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatSendError.networkError("Geçersiz sunucu yanıtı")
        }

        switch httpResponse.statusCode {
        case 200, 201, 204:
            // Başarılı
            return
        case 401:
            authManager.logout()
            throw ChatSendError.unauthorized
        case 429:
            throw ChatSendError.rateLimited
        default:
            let detail = String(data: data, encoding: .utf8) ?? "Bilinmeyen yanıt"
            throw ChatSendError.serverError(httpResponse.statusCode, detail)
        }
    }
}
