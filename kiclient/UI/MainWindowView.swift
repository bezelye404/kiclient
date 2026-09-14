import SwiftUI

public struct MainWindowView: View {
    @StateObject private var playerVM = PlayerViewModel()
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var authManager = KickAuthManager()

    @AppStorage("chatFontSize") private var chatFontSize: Double = 12.0
    @State private var channelInput: String = "xqc"
    @State private var directURLInput: String = ""
    @State private var showDirectURLEntry: Bool = false
    @State private var showChatSidebar: Bool = true
    @State private var showSettingsSheet: Bool = false
    @State private var showDevConsole: Bool = false

    public init() {}

    private var chatSender: KickChatSender {
        KickChatSender(authManager: authManager)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Üst Kontrol Çubuğu (Kanal, Durum ve Araçlar)
            HStack(spacing: 12) {
                Image(systemName: "tv.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)

                // Kanal Girişi
                HStack(spacing: 4) {
                    Text("kick.com/")
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))

                    TextField("kanal-adı", text: $channelInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 130)
                        .onSubmit {
                            triggerLoadChannel()
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

                Button(action: {
                    triggerLoadChannel()
                }) {
                    if playerVM.isLoadingChannel {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Label("Kanalı Aç", systemImage: "arrow.right.circle.fill")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(playerVM.isLoadingChannel || channelInput.trimmingCharacters(in: .whitespaces).isEmpty)

                Divider()
                    .frame(height: 20)

                // Canlı / Çevrimdışı Bilgi Rozeti
                if let info = playerVM.currentChannelInfo {
                    if info.isLive {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("CANLI")
                                .font(.caption.bold())
                                .foregroundColor(.red)

                            if let viewers = info.viewerCount {
                                Text("👁 \(formatViewers(viewers))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let title = info.streamTitle, !title.isEmpty {
                                Text("— \(title)")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    } else {
                        HStack(spacing: 6) {
                            Circle().fill(Color.gray).frame(width: 8, height: 8)
                            Text("ÇEVRİMDIŞI")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Geliştirici Konsolu Düğmesi
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDevConsole.toggle()
                    }
                }) {
                    Image(systemName: showDevConsole ? "terminal.fill" : "terminal")
                        .foregroundColor(showDevConsole ? .green : .primary)
                }
                .help("Geliştirici Konsolu (Dev Console) [⌘D]")
                .keyboardShortcut("d", modifiers: [.command])

                // Test HLS & Doğrudan URL
                Button(action: {
                    showDirectURLEntry.toggle()
                }) {
                    Image(systemName: "link")
                }
                .help("Özel HLS URL'si Gir")

                Button(action: {
                    playerVM.load(url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")
                }) {
                    Text("Test HLS")
                }
                .help("Halka açık test akışı oynat")

                // Ayarlar Düğmesi
                Button(action: {
                    showSettingsSheet = true
                }) {
                    Image(systemName: "gearshape.fill")
                }
                .help("Ayarlar (Kick OAuth, Kalite & Performans)")

                Divider()
                    .frame(height: 20)

                // Sohbet Göster/Gizle Butonu
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChatSidebar.toggle()
                    }
                }) {
                    Label(showChatSidebar ? "Sohbeti Gizle" : "Sohbeti Göster",
                          systemImage: showChatSidebar ? "sidebar.right" : "bubble.left.and.bubble.right.fill")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            // Özel URL Giriş Çubuğu (Açılırsa)
            if showDirectURLEntry {
                HStack(spacing: 8) {
                    TextField("Doğrudan .m3u8 HLS URL'si", text: $directURLInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            playerVM.load(url: directURLInput)
                        }
                    Button("Yükle") {
                        playerVM.load(url: directURLInput)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                Divider()
            }

            Divider()

            // Ana Sahne: Sol Video, Sağ Sohbet Tablosu
            HSplitView {
                // Sol: Video Sahnesi
                VStack(spacing: 0) {
                    ZStack {
                        MPVMetalView(controller: playerVM.controller)
                            .background(Color.black)

                        // Yükleniyor Göstergesi
                        if case .loading = playerVM.state {
                            ProgressView("Yayın yükleniyor...")
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding(16)
                                .background(Color.black.opacity(0.75))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        // Kanal Bildirimi (Offline veya Hata)
                        if let notice = playerVM.channelNotice {
                            VStack(spacing: 12) {
                                Image(systemName: "tv.slash")
                                    .font(.system(size: 44))
                                    .foregroundColor(.secondary)
                                Text(notice)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                Button("Yenile") {
                                    triggerLoadChannel()
                                }
                                .buttonStyle(BorderedButtonStyle())
                            }
                            .padding(24)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(12)
                        }
                    }

                    Divider()

                    // Alt Oynatma Kontrolleri
                    HStack(spacing: 16) {
                        Button(action: {
                            playerVM.togglePlayPause()
                        }) {
                            Image(systemName: playerVM.state == .playing ? "pause.fill" : "play.fill")
                                .imageScale(.medium)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(playerVM.currentURL.isEmpty)

                        Button(action: {
                            playerVM.stop()
                        }) {
                            Image(systemName: "stop.fill")
                                .imageScale(.medium)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(playerVM.state == .idle || playerVM.state == .stopped)

                        Button(action: {
                            playerVM.toggleMute()
                        }) {
                            Image(systemName: playerVM.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .imageScale(.medium)
                        }
                        .buttonStyle(BorderlessButtonStyle())

                        Slider(value: $playerVM.volume, in: 0...100)
                            .frame(width: 80)

                        // Kalite Seçici Menüsü
                        Menu {
                            ForEach(StreamQuality.allCases) { q in
                                Button(action: {
                                    playerVM.selectedQuality = q
                                }) {
                                    HStack {
                                        Text(q.rawValue)
                                        if playerVM.selectedQuality == q {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(playerVM.selectedQuality.rawValue)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(BorderlessButtonMenuStyle())
                        .frame(width: 75)

                        Spacer()

                        statusText(for: playerVM.state)

                        if playerVM.timePosition > 0 {
                            Text(formatTime(playerVM.timePosition))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(NSColor.windowBackgroundColor))
                }
                .frame(minWidth: 480)

                // Sağ: Sohbet Paneli (NSTableView Tabanlı)
                if showChatSidebar {
                    VStack(spacing: 0) {
                        // Sohbet Başlığı
                        HStack {
                            Text("CANLI SOHBET")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Spacer()

                            socketStatusBadge(chatVM.socketState)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))

                        Divider()

                        // Yüksek Hızlı NSTableView Sohbet Listesi (Dinamik Yazı Boyutu Destekli)
                        ChatListView(viewModel: chatVM, fontSize: CGFloat(chatFontSize))
                            .background(Color(NSColor.textBackgroundColor))

                        Divider()

                        // Mesaj Giriş ve Gönderim Çubuğu (Faz 4)
                        ChatInputBarView(
                            authManager: authManager,
                            chatSender: chatSender,
                            broadcasterId: playerVM.currentChannelInfo?.chatroomId,
                            onOpenSettings: {
                                showSettingsSheet = true
                            }
                        )
                    }
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)
                }
            }
            .frame(minWidth: 780, minHeight: 450)

            // Alt Geliştirici Konsolu Paneli (Açıksa)
            if showDevConsole {
                Divider()
                DevConsoleView(mpvController: playerVM.controller, onClose: {
                    withAnimation {
                        showDevConsole = false
                    }
                })
                .transition(.move(edge: .bottom))
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView(authManager: authManager, playerVM: playerVM)
        }
        .onAppear {
            if let lastSlug = UserDefaults.standard.string(forKey: "lastWatchedSlug"), !lastSlug.isEmpty {
                channelInput = lastSlug
            }
            if ProcessInfo.processInfo.arguments.contains("--autoplay") {
                triggerLoadChannel()
            }
        }
    }

    private func triggerLoadChannel() {
        Task {
            await playerVM.loadChannel(slug: channelInput)
            if let info = playerVM.currentChannelInfo {
                chatVM.connect(chatroomId: info.chatroomId)
            }
        }
    }

    @ViewBuilder
    private func statusText(for state: MPVPlaybackState) -> some View {
        switch state {
        case .idle:
            Text("Hazır").font(.caption).foregroundColor(.secondary)
        case .loading:
            Text("Yükleniyor...").font(.caption).foregroundColor(.orange)
        case .playing:
            Text("Oynatılıyor").font(.caption).foregroundColor(.green)
        case .paused:
            Text("Duraklatıldı").font(.caption).foregroundColor(.yellow)
        case .stopped:
            Text("Durduruldu").font(.caption).foregroundColor(.secondary)
        case .error(let msg):
            Text("Hata: \(msg)").font(.caption).foregroundColor(.red).lineLimit(1)
        }
    }

    @ViewBuilder
    private func socketStatusBadge(_ state: ChatSocketState) -> some View {
        switch state {
        case .disconnected:
            Text("Bağlı Değil").font(.caption2).foregroundColor(.secondary)
        case .connecting:
            HStack(spacing: 3) {
                ProgressView().scaleEffect(0.4).frame(width: 8, height: 8)
                Text("Bağlanıyor...").font(.caption2).foregroundColor(.orange)
            }
        case .connected:
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Bağlandı").font(.caption2).foregroundColor(.green)
            }
        case .reconnecting(let attempt, _):
            HStack(spacing: 3) {
                Circle().fill(Color.yellow).frame(width: 6, height: 6)
                Text("Tekrar (\(attempt))").font(.caption2).foregroundColor(.yellow)
            }
        case .error(let err):
            Text(err).font(.caption2).foregroundColor(.red).lineLimit(1)
        }
    }

    private func formatViewers(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
