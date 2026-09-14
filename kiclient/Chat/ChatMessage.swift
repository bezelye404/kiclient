import Foundation

public struct ChatBadge: Hashable, Sendable, Codable {
    public let type: String
    public let text: String?
    public let count: Int?

    public init(type: String, text: String? = nil, count: Int? = nil) {
        self.type = type
        self.text = text
        self.count = count
    }
}

public struct ChatMessage: Identifiable, Hashable, Sendable {
    public let id: String
    public let chatroomId: Int
    public let senderId: Int?
    public let senderUsername: String
    public let senderColorHex: String?
    public let content: String
    public let createdAt: Date
    public let badges: [ChatBadge]

    public init(
        id: String,
        chatroomId: Int,
        senderId: Int? = nil,
        senderUsername: String,
        senderColorHex: String? = nil,
        content: String,
        createdAt: Date = Date(),
        badges: [ChatBadge] = []
    ) {
        self.id = id
        self.chatroomId = chatroomId
        self.senderId = senderId
        self.senderUsername = senderUsername
        self.senderColorHex = senderColorHex
        self.content = content
        self.createdAt = createdAt
        self.badges = badges
    }

    /// KICK_API_NOTES.md §1.2 uyarınca Pusher'ın çift encode JSON verisini ayrıştırır
    public static func parsePusherData(event: String, rawDataString: String) throws -> ChatMessage? {
        guard event == "App\\Events\\ChatMessageEvent" || event == "ChatMessageEvent" else {
            return nil
        }

        guard let data = rawDataString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let id = (json["id"] as? String) ?? UUID().uuidString
        let chatroomId = (json["chatroom_id"] as? Int) ?? 0
        let content = (json["content"] as? String) ?? ""

        // Sender objesi
        let senderDict = json["sender"] as? [String: Any]
        let senderId = senderDict?["id"] as? Int
        let username = (senderDict?["username"] as? String) ?? "Anonim"

        // Kimlik (renk & rozetler)
        let identity = senderDict?["identity"] as? [String: Any]
        let colorHex = identity?["color"] as? String

        var badges: [ChatBadge] = []
        if let badgesArray = identity?["badges"] as? [[String: Any]] {
            for b in badgesArray {
                let type = (b["type"] as? String) ?? ""
                let text = b["text"] as? String
                let count = b["count"] as? Int
                badges.append(ChatBadge(type: type, text: text, count: count))
            }
        }

        // Zaman damgası
        var createdAtDate = Date()
        if let dateStr = json["created_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: dateStr) {
                createdAtDate = d
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                if let d2 = formatter.date(from: dateStr) {
                    createdAtDate = d2
                }
            }
        }

        return ChatMessage(
            id: id,
            chatroomId: chatroomId,
            senderId: senderId,
            senderUsername: username,
            senderColorHex: colorHex,
            content: content,
            createdAt: createdAtDate,
            badges: badges
        )
    }
}
