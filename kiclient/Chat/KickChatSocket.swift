import Foundation

public enum ChatSocketState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, nextRetryIn: Double)
    case error(String)
}

public protocol ChatSocketProtocol: AnyObject, Sendable {
    var state: ChatSocketState { get }
    var onMessageReceived: (@Sendable (ChatMessage) -> Void)? { get set }
    var onConnectionStateChanged: (@Sendable (ChatSocketState) -> Void)? { get set }
    func connect(chatroomId: Int)
    func disconnect()
}

public final class KickChatSocket: ChatSocketProtocol, @unchecked Sendable {
    public private(set) var state: ChatSocketState = .disconnected {
        didSet {
            onConnectionStateChanged?(state)
        }
    }

    public var onMessageReceived: (@Sendable (ChatMessage) -> Void)?
    public var onConnectionStateChanged: (@Sendable (ChatSocketState) -> Void)?

    private let pusherAppKey: String
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var currentChatroomId: Int?
    private var reconnectAttempt = 0
    private var isIntentionallyClosed = false
    private var heartbeatTimer: Timer?
    private let workQueue = DispatchQueue(label: "com.kiclient.chat.socket", qos: .userInitiated)

    public init(
        pusherAppKey: String = "32cbd69e4b950bf97679",
        session: URLSession = .shared
    ) {
        self.pusherAppKey = pusherAppKey
        self.session = session
    }

    deinit {
        disconnect()
    }

    public func connect(chatroomId: Int) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            self.isIntentionallyClosed = false
            self.currentChatroomId = chatroomId
            self.reconnectAttempt = 0
            self.startConnection()
        }
    }

    public func disconnect() {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            self.isIntentionallyClosed = true
            self.stopHeartbeat()
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
            self.state = .disconnected
        }
    }

    private func startConnection() {
        guard let chatroomId = currentChatroomId else { return }
        state = .connecting

        let urlString = "wss://ws-us2.pusher.com/app/\(pusherAppKey)?protocol=7&client=js&version=8.4.0&flash=false"
        guard let url = URL(string: urlString) else {
            state = .error("Geçersiz WebSocket URL'si")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        listenForMessages(task: task, expectedChatroomId: chatroomId)
    }

    private func listenForMessages(task: URLSessionWebSocketTask, expectedChatroomId: Int) {
        task.receive { [weak self] result in
            guard let self = self else { return }
            self.workQueue.async {
                guard self.webSocketTask === task, !self.isIntentionallyClosed else { return }

                switch result {
                case .failure(let error):
                    self.handleSocketFailure(error)
                case .success(let message):
                    self.handleIncomingSocketMessage(message, expectedChatroomId: expectedChatroomId)
                    self.listenForMessages(task: task, expectedChatroomId: expectedChatroomId)
                }
            }
        }
    }

    private func handleIncomingSocketMessage(_ message: URLSessionWebSocketTask.Message, expectedChatroomId: Int) {
        let text: String
        switch message {
        case .string(let s):
            text = s
        case .data(let d):
            text = String(data: d, encoding: .utf8) ?? ""
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = json["event"] as? String else {
            return
        }

        switch event {
        case "pusher:connection_established":
            // Başarılı el sıkışma -> Kanala abone ol
            state = .connected
            reconnectAttempt = 0
            subscribeToChatroom(expectedChatroomId)
            startHeartbeat()

        case "pusher:ping":
            // Pusher ping'ine anında pong ile yanıt ver
            sendRaw(jsonString: "{\"event\":\"pusher:pong\",\"data\":{}}")

        case "App\\Events\\ChatMessageEvent", "ChatMessageEvent":
            if let dataString = json["data"] as? String {
                if let chatMsg = try? ChatMessage.parsePusherData(event: event, rawDataString: dataString) {
                    onMessageReceived?(chatMsg)
                }
            }

        default:
            break
        }
    }

    private func subscribeToChatroom(_ chatroomId: Int) {
        let subscribePayload = """
        {"event":"pusher:subscribe","data":{"auth":"","channel":"chatrooms.\(chatroomId).v2"}}
        """
        sendRaw(jsonString: subscribePayload)
    }

    private func sendRaw(jsonString: String) {
        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                print("[KickChatSocket] Gönderme hatası: \(error)")
            }
        }
    }

    private func handleSocketFailure(_ error: Error) {
        guard !isIntentionallyClosed else { return }
        stopHeartbeat()
        webSocketTask = nil

        reconnectAttempt += 1
        // Üstel geri çekilme: min(2^attempt, 30.0) + küçük rastgele jitter
        let baseDelay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        let jitter = Double.random(in: 0.1...0.9)
        let delay = baseDelay + jitter

        state = .reconnecting(attempt: reconnectAttempt, nextRetryIn: delay)

        workQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isIntentionallyClosed else { return }
            self.startConnection()
        }
    }

    private func startHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            self?.stopHeartbeat()
            self?.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { [weak self] _ in
                self?.workQueue.async {
                    self?.sendRaw(jsonString: "{\"event\":\"pusher:ping\",\"data\":{}}")
                }
            }
        }
    }

    private func stopHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = nil
        }
    }
}
