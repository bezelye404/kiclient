import SwiftUI

public struct SettingsView: View {
    @ObservedObject var authManager: KickAuthManager
    @ObservedObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("chatFontSize") private var chatFontSize: Double = 12.0
    @State private var clientIdInput: String = ""
    @State private var redirectURIInput: String = ""
    @State private var isLoggingIn: Bool = false
    @State private var errorMessage: String? = nil
    @State private var currentRSSMB: Double = 0.0

    public init(authManager: KickAuthManager, playerVM: PlayerViewModel) {
        self.authManager = authManager
        self.playerVM = playerVM
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
                    // Yayın & Kalite Ayarları
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Yayın & Oynatma")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Yayın Kalitesi:")
                                    .font(.subheadline)
                                Spacer()
                                Picker("", selection: $playerVM.selectedQuality) {
                                    ForEach(StreamQuality.allCases) { q in
                                        Text(q.rawValue).tag(q)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 140)
                            }

                            Toggle("Arka Plan Eko Modu (Pencere gizliyken GPU'yu duraklat)", isOn: $playerVM.backgroundEcoModeEnabled)
                                .font(.caption)
                                .help("Pencere simge durumuna küçültüldüğünde veya başka pencerenin arkasında kaldığında video render durdurulur, ses ve sohbet devam eder.")
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    Divider()

                    // Sohbet & Görünüm Ayarları
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sohbet & Görünüm")
                            .font(.headline)

                        HStack {
                            Text("Yazı Boyutu:")
                                .font(.subheadline)
                            Spacer()
                            Picker("", selection: $chatFontSize) {
                                Text("Küçük (11 pt)").tag(11.0)
                                Text("Normal (13 pt)").tag(13.0)
                                Text("Büyük (15 pt)").tag(15.0)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 240)
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    Divider()

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

                    // Performans ve Donanım Hızlandırma Bilgisi
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Performans & Donanım Hızlandırma")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Canlı RSS Bellek:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1f MB", currentRSSMB))
                                    .bold()
                                    .foregroundColor(.green)
                            }
                            HStack {
                                Text("Video Decode:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Apple VideoToolbox (Donanım)")
                                    .bold()
                            }
                            HStack {
                                Text("Render Çıktısı:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Metal (gpu-next)")
                                    .bold()
                            }
                            HStack {
                                Text("Demuxer Bellek Sınırı:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("32 MiB max / 16 MiB back")
                                    .bold()
                            }
                            HStack {
                                Text("Görsel Önbelleği (NSCache):")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Önbelleği Temizle") {
                                    ImageCacheManager.shared.clear()
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .font(.caption)
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
        .frame(width: 500, height: 560)
        .onAppear {
            clientIdInput = authManager.clientId
            redirectURIInput = authManager.redirectURI
            currentRSSMB = AppLogger.getMemoryUsageMB()
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
