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
        VStack(spacing: DesignTokens.Spacing.xs) {
            if authManager.isAuthenticated {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        TextField("Bir mesaj gönder...", text: $messageText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.body)
                            .onSubmit {
                                triggerSendMessage()
                            }
                            .disabled(isSending || broadcasterId == nil)

                        if !messageText.isEmpty {
                            Button(action: { messageText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                            .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                    )

                    Button(action: {
                        triggerSendMessage()
                    }) {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .controlSize(.regular)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
                    .disabled(isSending || messageText.trimmingCharacters(in: .whitespaces).isEmpty || broadcasterId == nil)
                }
            } else {
                // HIG §6.3 Uyumlu Çağrı Kartı (CTA Card)
                VStack(spacing: DesignTokens.Spacing.sm) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Sohbete katılmak için hesap bağlayın")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(action: onOpenSettings) {
                        Text("Giriş Yap")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(DesignTokens.Spacing.md)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                        .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                )
            }

            if let err = sendError {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(DesignTokens.Colors.error)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(.regularMaterial)
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
