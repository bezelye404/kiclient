import Foundation

public struct ChannelInfo: Equatable, Sendable {
    public let slug: String
    public let username: String
    public let chatroomId: Int
    public let playbackURL: String?
    public let isLive: Bool
    public let streamTitle: String?
    public let viewerCount: Int?
    public let avatarURL: String?

    public init(
        slug: String,
        username: String,
        chatroomId: Int,
        playbackURL: String?,
        isLive: Bool,
        streamTitle: String? = nil,
        viewerCount: Int? = nil,
        avatarURL: String? = nil
    ) {
        self.slug = slug
        self.username = username
        self.chatroomId = chatroomId
        self.playbackURL = playbackURL
        self.isLive = isLive
        self.streamTitle = streamTitle
        self.viewerCount = viewerCount
        self.avatarURL = avatarURL
    }
}

public enum ChannelAPIError: LocalizedError, Equatable {
    case invalidSlug(String)
    case notFound(String)
    case rateLimitedOrBlocked(Int)
    case invalidResponse
    case decodingFailed(String)
    case networkFailure(String)
    case channelOffline(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSlug(let slug):
            return "Geçersiz kanal adı: '\(slug)'."
        case .notFound(let slug):
            return "'\(slug)' adlı Kick kanalı bulunamadı."
        case .rateLimitedOrBlocked(let code):
            return "Kick sunucusu isteği reddetti (HTTP \(code)). Lütfen birkaç saniye sonra tekrar deneyin."
        case .invalidResponse:
            return "Sunucudan geçersiz bir yanıt alındı."
        case .decodingFailed(let detail):
            return "Kanal verisi ayrıştırılamadı: \(detail)"
        case .networkFailure(let detail):
            return "Ağ bağlantı hatası: \(detail)"
        case .channelOffline(let slug):
            return "'\(slug)' kanalı şu anda canlı yayında değil."
        }
    }
}

public protocol ChannelResolving: Sendable {
    func resolveChannel(slug: String) async throws -> ChannelInfo
}

public final class KickChannelAPI: ChannelResolving, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func resolveChannel(slug: String) async throws -> ChannelInfo {
        let cleanSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanSlug.isEmpty,
              let url = URL(string: "https://kick.com/api/v2/channels/\(cleanSlug)") else {
            throw ChannelAPIError.invalidSlug(slug)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ChannelAPIError.networkFailure(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChannelAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try Self.parseChannelJSON(data, slug: cleanSlug)
        case 404:
            throw ChannelAPIError.notFound(cleanSlug)
        case 403, 429:
            throw ChannelAPIError.rateLimitedOrBlocked(httpResponse.statusCode)
        default:
            throw ChannelAPIError.rateLimitedOrBlocked(httpResponse.statusCode)
        }
    }

    /// Saf fonksiyon: TESTING.md gereğince izole birim testleri için JSON ayrıştırma mantığı
    public static func parseChannelJSON(_ data: Data, slug: String) throws -> ChannelInfo {
        let jsonObject: [String: Any]
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ChannelAPIError.decodingFailed("JSON kök nesnesi sözlük formatında değil.")
            }
            jsonObject = dict
        } catch {
            throw ChannelAPIError.decodingFailed(error.localizedDescription)
        }

        // chatroom.id
        guard let chatroom = jsonObject["chatroom"] as? [String: Any],
              let chatroomId = chatroom["id"] as? Int else {
            throw ChannelAPIError.decodingFailed("chatroom.id alanı eksik veya geçersiz.")
        }

        // user bilgileri
        let userDict = jsonObject["user"] as? [String: Any]
        let username = (userDict?["username"] as? String) ?? slug
        let avatarURL = userDict?["profile_pic"] as? String

        // livestream ve playback URL
        let livestream = jsonObject["livestream"] as? [String: Any]
        let isLive = (livestream != nil)
        var playbackURL: String? = nil

        if isLive {
            if let directPlayback = jsonObject["playback_url"] as? String, !directPlayback.isEmpty {
                playbackURL = directPlayback.replacingOccurrences(of: "\\/", with: "/")
            } else if let lsPlayback = livestream?["playback_url"] as? String, !lsPlayback.isEmpty {
                playbackURL = lsPlayback.replacingOccurrences(of: "\\/", with: "/")
            }
        }

        let streamTitle = livestream?["session_title"] as? String
        let viewerCount = livestream?["viewer_count"] as? Int

        return ChannelInfo(
            slug: slug,
            username: username,
            chatroomId: chatroomId,
            playbackURL: playbackURL,
            isLive: isLive,
            streamTitle: streamTitle,
            viewerCount: viewerCount,
            avatarURL: avatarURL
        )
    }
}
