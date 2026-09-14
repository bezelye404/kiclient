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
            // Ana Sahne: Sol Video, Sağ Sohbet Paneli
            HSplitView {
                // Sol: Video Sahnesi
                VStack(spacing: 0) {
                    ZStack {
                        Color.black

                        MPVMetalView(controller: playerVM.controller)

                        // Boş Durum (Empty State - Henüz yayın seçilmemiş)
                        if playerVM.currentURL.isEmpty && playerVM.channelNotice == nil {
                            VStack(spacing: DesignTokens.Spacing.sm) {
                                Image(systemName: "tv")
                                    .font(.system(size: 42))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .imageScale(.large)
                                Text("Yayın izlemek için yukarıdan bir kanal girin")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Yükleniyor Göstergesi
                        if case .loading = playerVM.state {
                            VStack(spacing: DesignTokens.Spacing.md) {
                                ProgressView()
                                    .controlSize(.regular)
                                Text("Yayın yükleniyor...")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .padding(DesignTokens.Spacing.lg)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        }

                        // Kanal Bildirimi (Offline veya Hata)
                        if let notice = playerVM.channelNotice {
                            VStack(spacing: DesignTokens.Spacing.md) {
                                Image(systemName: "tv.slash")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text(notice)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                Button("Yeniden Dene") {
                                    triggerLoadChannel()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                            }
                            .padding(DesignTokens.Spacing.xl)
                            .background(Color.black.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.large))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.large)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    // Alt Kontrol Çubuğu (Apple HIG uyumlu dikey baseline hizalama ve 8pt marginler)
                    HStack(spacing: DesignTokens.Spacing.md) {
                        Button(action: {
                            playerVM.togglePlayPause()
                        }) {
                            Image(systemName: playerVM.state == .playing ? "pause.fill" : "play.fill")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.plain)
                        .disabled(playerVM.currentURL.isEmpty)
                        .accessibilityLabel(playerVM.state == .playing ? "Duraklat" : "Oynat")

                        Button(action: {
                            playerVM.stop()
                        }) {
                            Image(systemName: "stop.fill")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.plain)
                        .disabled(playerVM.state == .idle || playerVM.state == .stopped)
                        .accessibilityLabel("Durdur")

                        Divider().frame(height: 14)

                        // Ses Kontrolü
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Button(action: {
                                playerVM.toggleMute()
                            }) {
                                Image(systemName: playerVM.isMuted ? "speaker.slash.fill" : (playerVM.volume < 30 ? "speaker.1.fill" : "speaker.wave.2.fill"))
                                    .imageScale(.medium)
                                    .foregroundColor(playerVM.isMuted ? .secondary : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Sessize Al")

                            Slider(value: $playerVM.volume, in: 0...100)
                                .frame(width: 80)
                                .controlSize(.small)
                                .accessibilityLabel("Ses Seviyesi")
                        }

                        // Kalite Seçici Menüsü (Native HIG Menu)
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
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: "slider.horizontal.3")
                                    .imageScale(.small)
                                Text(playerVM.selectedQuality.rawValue)
                                    .font(.caption.weight(.medium))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel("Yayın Kalitesi")

                        Spacer()

                        // Sakin Durum Göstergesi
                        statusIndicator(for: playerVM.state)

                        if playerVM.timePosition > 0 {
                            Text(formatTime(playerVM.timePosition))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.vertical, DesignTokens.Spacing.md)
                    .background(.regularMaterial)
                }
                .layoutPriority(1)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

                // Sağ: Sohbet Paneli (Belirgin Divider ile Ayrılmış)
                if showChatSidebar {
                    VStack(spacing: 0) {
                        // Sohbet Başlığı (HIG: .headline + .secondary, sakin gösterge)
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Text("Canlı Sohbet")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Spacer()

                            socketStatusBadge(chatVM.socketState)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background(.regularMaterial)

                        Divider()

                        // Yüksek Hızlı NSTableView Sohbet Listesi
                        ChatListView(viewModel: chatVM, fontSize: CGFloat(chatFontSize))
                            .background(Color(nsColor: .textBackgroundColor))

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
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 450)
                }
            }
            .frame(minWidth: 800, minHeight: 480)

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
        .background(WindowAccessor { window in
            window.titleVisibility = .hidden
            window.title = "kiclient"
        })
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "tv")
                        .foregroundColor(.secondary)
                        .imageScale(.small)

                    TextField("Kanal adı...", text: $channelInput)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .frame(width: 130)
                        .onSubmit {
                            triggerLoadChannel()
                        }

                    if playerVM.isLoadingChannel {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                            .frame(width: 16, height: 16)
                    } else {
                        Button(action: {
                            triggerLoadChannel()
                        }) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.accentColor)
                                .imageScale(.medium)
                        }
                        .buttonStyle(.plain)
                        .disabled(channelInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Kanalı Yükle")
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                        .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                )
                .padding(.leading, DesignTokens.Spacing.xl + 4)
            }

            ToolbarItemGroup(placement: .principal) {
                if let info = playerVM.currentChannelInfo {
                    if info.isLive {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            // Sakin CANLI Rozeti (İnce kontur + sakin kırmızı nokta)
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Circle()
                                    .fill(DesignTokens.Colors.liveIndicator)
                                    .frame(width: 6, height: 6)
                                Text("CANLI")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .overlay(
                                Capsule()
                                    .strokeBorder(DesignTokens.Colors.separator, lineWidth: 1)
                            )

                            if let viewers = info.viewerCount {
                                Text("👁 \(formatViewers(viewers))")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)
                            }

                            if let title = info.streamTitle, !title.isEmpty {
                                Text(title)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .textCase(nil)
                                    .frame(maxWidth: 240)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Circle()
                                .fill(Color.secondary)
                                .frame(width: 6, height: 6)
                            Text("Çevrimdışı")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
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
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Özel HLS URL'si Gir")
                .popover(isPresented: $showDirectURLEntry) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        Text("Doğrudan Akış URL'si")
                            .font(.headline)
                        HStack {
                            TextField("https://.../master.m3u8", text: $directURLInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 280)
                            Button("Oynat") {
                                playerVM.load(url: directURLInput)
                                showDirectURLEntry = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button("Mux Test Akışı Yükle") {
                            directURLInput = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
                            playerVM.load(url: directURLInput)
                            showDirectURLEntry = false
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                    .padding(DesignTokens.Spacing.lg)
                }

                // Geliştirici Konsolu Düğmesi
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        showDevConsole.toggle()
                    }
                }) {
                    Image(systemName: "terminal")
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(showDevConsole ? .accentColor : .primary)
                }
                .accessibilityLabel("Geliştirici Konsolu")
                .keyboardShortcut("d", modifiers: [.command])

                // Ayarlar Düğmesi
                Button(action: {
                    showSettingsSheet = true
                }) {
                    Image(systemName: "gearshape")
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Ayarlar")
                .keyboardShortcut(",", modifiers: [.command])

                // Sohbet Göster/Gizle Butonu
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChatSidebar.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.trailing")
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(showChatSidebar ? .accentColor : .secondary)
                }
                .accessibilityLabel("Sohbeti Göster veya Gizle")
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
    private func statusIndicator(for state: MPVPlaybackState) -> some View {
        switch state {
        case .idle:
            Text("Hazır").font(.caption).foregroundColor(.secondary)
        case .loading:
            HStack(spacing: DesignTokens.Spacing.xs) {
                ProgressView().controlSize(.mini)
                Text("Yükleniyor...").font(.caption).foregroundColor(.secondary)
            }
        case .playing:
            HStack(spacing: DesignTokens.Spacing.xs) {
                Circle().fill(DesignTokens.Colors.connected).frame(width: 6, height: 6)
                Text("Oynatılıyor").font(.caption).foregroundColor(.secondary)
            }
        case .paused:
            HStack(spacing: DesignTokens.Spacing.xs) {
                Circle().fill(DesignTokens.Colors.warning).frame(width: 6, height: 6)
                Text("Duraklatıldı").font(.caption).foregroundColor(.secondary)
            }
        case .stopped:
            Text("Durduruldu").font(.caption).foregroundColor(.secondary)
        case .error(let msg):
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "exclamationmark.circle").foregroundColor(DesignTokens.Colors.error).font(.caption2)
                Text(msg).font(.caption).foregroundColor(DesignTokens.Colors.error).lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func socketStatusBadge(_ state: ChatSocketState) -> some View {
        switch state {
        case .disconnected:
            HStack(spacing: DesignTokens.Spacing.xs) {
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                Text("Bağlı Değil").font(.caption2).foregroundColor(.secondary)
            }
        case .connecting:
            HStack(spacing: DesignTokens.Spacing.xs) {
                ProgressView().controlSize(.mini)
                Text("Bağlanıyor...").font(.caption2).foregroundColor(.secondary)
            }
        case .connected:
            HStack(spacing: DesignTokens.Spacing.xs) {
                Circle().fill(DesignTokens.Colors.connected).frame(width: 6, height: 6)
                Text("Bağlandı").font(.caption2).foregroundColor(.secondary)
            }
        case .reconnecting(let attempt, _):
            HStack(spacing: DesignTokens.Spacing.xs) {
                Circle().fill(DesignTokens.Colors.warning).frame(width: 6, height: 6)
                Text("Tekrar (\(attempt))").font(.caption2).foregroundColor(.secondary)
            }
        case .error(let err):
            Text(err).font(.caption2).foregroundColor(DesignTokens.Colors.error).lineLimit(1)
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

// MARK: - Native Window Accessor
struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            callback(window)
        }
    }
}
