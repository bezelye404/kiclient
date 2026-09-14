import SwiftUI

public struct ChatInputBarView: View {
    @ObservedObject var authManager: KickAuthManager
    let chatSender: ChatSending
    let broadcasterId: Int?
    let onOpenSettings: () -> Void

    @State private var messageText: String = ""
    @State private var isSending: Bool = false
    @State private var sendError: String? = nil

    public init(
        authManager: KickAuthManager,
        chatSender: ChatSending,
        broadcasterId: Int?,
        onOpenSettings: @escaping () -> Void
    ) {
        self.authManager = authManager
        self.chatSender = chatSender
        self.broadcasterId = broadcasterId
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: 4) {
            if authManager.isAuthenticated {
                HStack(spacing: 8) {
                    TextField("Bir mesaj gönder...", text: $messageText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(5)
                        .onSubmit {
                            triggerSendMessage()
                        }
                        .disabled(isSending || broadcasterId == nil)

                    Button(action: {
                        triggerSendMessage()
                    }) {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .disabled(isSending || messageText.trimmingCharacters(in: .whitespaces).isEmpty || broadcasterId == nil)
                }
            } else {
                HStack {
                    Text("Sohbete yazmak için giriş yapın:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: onOpenSettings) {
                        Text("Giriş Yap")
                            .font(.caption.bold())
                    }
                    .buttonStyle(BorderedButtonStyle())
                }
            }

            if let err = sendError {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func triggerSendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let bId = broadcasterId else { return }

        isSending = true
        sendError = nil

        Task { @MainActor in
            do {
                try await chatSender.sendMessage(content: text, broadcasterUserId: bId)
                messageText = ""
                isSending = false
            } catch {
                isSending = false
                sendError = error.localizedDescription
            }
        }
    }
}
