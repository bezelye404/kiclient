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
                    HStack(spacing: 6) {
                        TextField("Bir mesaj gönder...", text: $messageText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 12))
                            .onSubmit {
                                triggerSendMessage()
                            }
                            .disabled(isSending || broadcasterId == nil)

                        if !messageText.isEmpty {
                            Button(action: { messageText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                    Button(action: {
                        triggerSendMessage()
                    }) {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .controlSize(.regular)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(isSending || messageText.trimmingCharacters(in: .whitespaces).isEmpty || broadcasterId == nil)
                }
            } else {
                Button(action: onOpenSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                        Text("Sohbete katılmak için giriş yapın")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.regular)
            }

            if let err = sendError {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
