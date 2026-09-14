import SwiftUI

public struct SettingsView: View {
    @ObservedObject var authManager: KickAuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var clientIdInput: String = ""
    @State private var redirectURIInput: String = ""
    @State private var isLoggingIn: Bool = false
    @State private var errorMessage: String? = nil

    public init(authManager: KickAuthManager) {
        self.authManager = authManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Başlık
            HStack {
                Text("Ayarlar")
                    .font(.title2.bold())
                Spacer()
                Button("Kapat") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Kick OAuth Bölümü
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Kick Hesabı & OAuth 2.1")
                            .font(.headline)

                        Text("Sohbete kendi adınızla mesaj gönderebilmek için bir Kick Developer uygulaması gereklidir.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Client ID:")
                                .font(.caption.bold())
                            TextField("Kick App Client ID", text: $clientIdInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())

                            Text("Redirect URI:")
                                .font(.caption.bold())
                            TextField("kiclient://oauth-callback", text: $redirectURIInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)

                        // Giriş Durumu & Butonlar
                        if authManager.isAuthenticated {
                            HStack {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("Giriş Yapıldı (Token Keychain'de)")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                Spacer()
                                Button("Çıkış Yap") {
                                    authManager.logout()
                                }
                                .buttonStyle(BorderedButtonStyle())
                            }
                            .padding(.top, 4)
                        } else {
                            HStack {
                                Button(action: {
                                    triggerLogin()
                                }) {
                                    if isLoggingIn {
                                        ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                        Text("Giriş Yapılıyor...")
                                    } else {
                                        Label("Kick ile Giriş Yap", systemImage: "person.crop.circle.badge.checkmark")
                                    }
                                }
                                .buttonStyle(BorderedProminentButtonStyle())
                                .disabled(isLoggingIn || clientIdInput.trimmingCharacters(in: .whitespaces).isEmpty)

                                Spacer()
                            }
                        }

                        if let err = errorMessage ?? authManager.authErrorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Link("Kick Developer Portal'ı Aç (kick.com/settings/developer)",
                             destination: URL(string: "https://kick.com/settings/developer")!)
                            .font(.caption)
                    }

                    Divider()

                    // Performans ve mpv Bilgisi
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Performans & Donanım Hızlandırma")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Video Decode:")
                                    .foregroundColor(.secondary)
                                Text("Apple VideoToolbox (Donanım)")
                                    .bold()
                            }
                            HStack {
                                Text("Render Çıktısı:")
                                    .foregroundColor(.secondary)
                                Text("Metal (gpu-next)")
                                    .bold()
                            }
                            HStack {
                                Text("Demuxer Bellek Sınırı:")
                                    .foregroundColor(.secondary)
                                Text("32 MiB max / 16 MiB back")
                                    .bold()
                            }
                            HStack {
                                Text("Sohbet Bellek Sınırı:")
                                    .foregroundColor(.secondary)
                                Text("300 mesaj (Rolling Dequeue)")
                                    .bold()
                            }
                        }
                        .font(.caption)
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 460)
        .onAppear {
            clientIdInput = authManager.clientId
            redirectURIInput = authManager.redirectURI
        }
    }

    private func triggerLogin() {
        authManager.clientId = clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        authManager.redirectURI = redirectURIInput.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        isLoggingIn = true

        Task { @MainActor in
            do {
                try await authManager.startLogin()
                isLoggingIn = false
            } catch {
                isLoggingIn = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
