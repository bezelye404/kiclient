import Foundation
import Combine

public final class ChatViewModel: ObservableObject {
    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var socketState: ChatSocketState = .disconnected

    public let maxMessages: Int
    public let batchInterval: TimeInterval

    private let socket: ChatSocketProtocol
    private var pendingMessages: [ChatMessage] = []
    private var flushTimer: Timer?
    private let queue = DispatchQueue(label: "com.kiclient.chat.viewmodel", qos: .userInteractive)

    public init(
        socket: ChatSocketProtocol = KickChatSocket(),
        maxMessages: Int = 300,
        batchInterval: TimeInterval = 0.1 // 100 ms (~10 Hz coalescing)
    ) {
        self.socket = socket
        self.maxMessages = maxMessages
        self.batchInterval = batchInterval
        setupBindings()
    }

    deinit {
        stopFlushTimer()
        socket.disconnect()
    }

    private func setupBindings() {
        socket.onMessageReceived = { [weak self] message in
            self?.enqueueMessage(message)
        }

        socket.onConnectionStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                self?.socketState = state
            }
        }
    }

    public func connect(chatroomId: Int) {
        clear()
        startFlushTimer()
        socket.connect(chatroomId: chatroomId)
    }

    public func disconnect() {
        stopFlushTimer()
        socket.disconnect()
    }

    public func clear() {
        queue.sync {
            pendingMessages.removeAll()
        }
        DispatchQueue.main.async {
            self.messages.removeAll()
        }
    }

    /// Mesajı kuyruğa alır. TESTING.md için doğrudan test edilebilir.
    public func enqueueMessage(_ message: ChatMessage) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingMessages.append(message)
        }
    }

    /// Tampondaki birikmiş mesajları UI'a flush eder
    public func flushPendingMessages() {
        var toAdd: [ChatMessage] = []
        queue.sync {
            if !pendingMessages.isEmpty {
                toAdd = pendingMessages
                pendingMessages.removeAll()
            }
        }

        guard !toAdd.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var combined = self.messages + toAdd
            if combined.count > self.maxMessages {
                let excess = combined.count - self.maxMessages
                combined.removeFirst(excess)
            }
            self.messages = combined
        }
    }

    private func startFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopFlushTimer()
            self.flushTimer = Timer.scheduledTimer(withTimeInterval: self.batchInterval, repeats: true) { [weak self] _ in
                self?.flushPendingMessages()
            }
        }
    }

    private func stopFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.flushTimer?.invalidate()
            self?.flushTimer = nil
        }
    }
}
