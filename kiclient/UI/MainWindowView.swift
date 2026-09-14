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
            // Ana Sahne: Sol Video, Sağ Sohbet Tablosu
            HSplitView {
                // Sol: Video Sahnesi
                VStack(spacing: 0) {
                    ZStack {
                        Color.black

                        MPVMetalView(controller: playerVM.controller)

                        // Yükleniyor Göstergesi
                        if case .loading = playerVM.state {
                            VStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(1.1)
                                Text("Yayın yükleniyor...")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .padding(20)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        }

                        // Kanal Bildirimi (Offline veya Hata)
                        if let notice = playerVM.channelNotice {
                            VStack(spacing: 12) {
                                Image(systemName: "tv.slash.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text(notice)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                Button("Yeniden Dene") {
                                    triggerLoadChannel()
                                }
                                .buttonStyle(BorderedProminentButtonStyle())
                                .controlSize(.small)
                            }
                            .padding(24)
                            .background(Color.black.opacity(0.82))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    // Alt Şık Oynatma Kontrolleri
                    HStack(spacing: 14) {
                        Button(action: {
                            playerVM.togglePlayPause()
                        }) {
                            Image(systemName: playerVM.state == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(playerVM.currentURL.isEmpty)
                        .help(playerVM.state == .playing ? "Duraklat" : "Oynat")

                        Button(action: {
                            playerVM.stop()
                        }) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(playerVM.state == .idle || playerVM.state == .stopped)
                        .help("Durdur")

                        Divider().frame(height: 14)

                        // Ses Kontrolü
                        HStack(spacing: 6) {
                            Button(action: {
                                playerVM.toggleMute()
                            }) {
                                Image(systemName: playerVM.isMuted ? "speaker.slash.fill" : (playerVM.volume < 30 ? "speaker.1.fill" : "speaker.wave.2.fill"))
                                    .font(.system(size: 12))
                                    .foregroundColor(playerVM.isMuted ? .red : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Slider(value: $playerVM.volume, in: 0...100)
                                .frame(width: 75)
                                .controlSize(.small)
                        }

                        // Kalite Seçici Menüsü (Modern Rozet)
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
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 9))
                                Text(playerVM.selectedQuality.rawValue)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .menuStyle(BorderlessButtonMenuStyle())
                        .fixedSize()

                        Spacer()

                        statusBadge(for: playerVM.state)

                        if playerVM.timePosition > 0 {
                            Text(formatTime(playerVM.timePosition))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.windowBackgroundColor))
                }
                .layoutPriority(1)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

                // Sağ: Sohbet Paneli (NSTableView Tabanlı)
                if showChatSidebar {
                    VStack(spacing: 0) {
                        // Sohbet Başlığı
                        HStack(spacing: 8) {
                            Text("CANLI SOHBET")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)

                            Spacer()

                            socketStatusBadge(chatVM.socketState)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(NSColor.controlBackgroundColor))

                        Divider()

                        // Yüksek Hızlı NSTableView Sohbet Listesi
                        ChatListView(viewModel: chatVM, fontSize: CGFloat(chatFontSize))
                            .background(Color(NSColor.textBackgroundColor))

                        Divider()

                        // Mesaj Giriş ve Gönderim Çubuğu
                        ChatInputBarView(
                            authManager: authManager,
                            chatSender: chatSender,
                            broadcasterId: playerVM.currentChannelInfo?.chatroomId,
                            onOpenSettings: {
                                showSettingsSheet = true
                            }
                        )
                    }
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 450)
                }
            }
            .frame(minWidth: 780, minHeight: 480)

            // Alt Geliştirici Konsolu Paneli (Açıksa Çekmece Olarak Açılır)
            if showDevConsole {
                Divider()
                DevConsoleView(mpvController: playerVM.controller, onClose: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        showDevConsole = false
                    }
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "play.tv.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14, weight: .bold))

                    HStack(spacing: 2) {
                        Text("kick.com/")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))

                        TextField("kanal", text: $channelInput)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(width: 110)
                            .onSubmit {
                                triggerLoadChannel()
                            }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                    Button(action: {
                        triggerLoadChannel()
                    }) {
                        if playerVM.isLoadingChannel {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 15))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(playerVM.isLoadingChannel || channelInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Kanalı Yükle [Enter]")
                }
            }

            ToolbarItemGroup(placement: .principal) {
                if let info = playerVM.currentChannelInfo {
                    if info.isLive {
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 7, height: 7)
                                Text("CANLI")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Capsule())

                            if let viewers = info.viewerCount {
                                HStack(spacing: 3) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 10))
                                    Text(formatViewers(viewers))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                }
                                .foregroundColor(.secondary)
                            }

                            if let title = info.streamTitle, !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 260)
                            }
                        }
                    } else {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 6, height: 6)
                            Text("ÇEVRİMDIŞI")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }

            ToolbarItemGroup(placement: .automatic) {
                // Doğrudan URL popover
                Button(action: {
                    showDirectURLEntry.toggle()
                }) {
                    Image(systemName: "link")
                }
                .help("Özel .m3u8 HLS URL'si Gir")
                .popover(isPresented: $showDirectURLEntry) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Doğrudan Akış URL'si")
                            .font(.caption.bold())
                        HStack {
                            TextField("https://.../master.m3u8", text: $directURLInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 280)
                            Button("Oynat") {
                                playerVM.load(url: directURLInput)
                                showDirectURLEntry = false
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                        Button("Mux Test Akışı Yükle") {
                            directURLInput = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
                            playerVM.load(url: directURLInput)
                            showDirectURLEntry = false
                        }
                        .font(.caption)
                        .buttonStyle(LinkButtonStyle())
                    }
                    .padding(14)
                }

                // Geliştirici Konsolu Düğmesi
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        showDevConsole.toggle()
                    }
                }) {
                    Image(systemName: showDevConsole ? "terminal.fill" : "terminal")
                        .foregroundColor(showDevConsole ? .green : .primary)
                }
                .help("Geliştirici Konsolu (Dev Console) [⌘D]")
                .keyboardShortcut("d", modifiers: [.command])

                // Ayarlar Düğmesi
                Button(action: {
                    showSettingsSheet = true
                }) {
                    Image(systemName: "gearshape")
                }
                .help("Ayarlar (Kick OAuth, Kalite & Performans) [⌘,]")
                .keyboardShortcut(",", modifiers: [.command])

                // Sohbet Göster/Gizle Butonu
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChatSidebar.toggle()
                    }
                }) {
                    Image(systemName: showChatSidebar ? "sidebar.right" : "bubble.left.and.bubble.right")
                        .foregroundColor(showChatSidebar ? .accentColor : .secondary)
                }
                .help("Sohbeti Göster / Gizle [⌘⌥C]")
                .keyboardShortcut("c", modifiers: [.command, .option])
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
    private func statusBadge(for state: MPVPlaybackState) -> some View {
        switch state {
        case .idle:
            Text("Hazır").font(.caption).foregroundColor(.secondary)
        case .loading:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.4).frame(width: 8, height: 8)
                Text("Yükleniyor...").font(.caption).foregroundColor(.orange)
            }
        case .playing:
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Oynatılıyor").font(.caption.bold()).foregroundColor(.green)
            }
        case .paused:
            HStack(spacing: 4) {
                Circle().fill(Color.yellow).frame(width: 6, height: 6)
                Text("Duraklatıldı").font(.caption).foregroundColor(.yellow)
            }
        case .stopped:
            Text("Durduruldu").font(.caption).foregroundColor(.secondary)
        case .error(let msg):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.caption2)
                Text(msg).font(.caption).foregroundColor(.red).lineLimit(1)
            }
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
