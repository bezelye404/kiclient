import Foundation
import Combine
import AppKit

public enum StreamQuality: String, CaseIterable, Identifiable, Sendable {
    case auto = "Otomatik"
    case q1080p = "1080p60"
    case q720p = "720p60"
    case q480p = "480p30"
    case q160p = "160p"

    public var id: String { rawValue }

    public var maxBitrate: String? {
        switch self {
        case .auto: return "max"
        case .q1080p: return "8500000"
        case .q720p: return "4500000"
        case .q480p: return "2000000"
        case .q160p: return "500000"
        }
    }
}

public final class PlayerViewModel: ObservableObject {
    @Published public var state: MPVPlaybackState = .idle
    @Published public var currentURL: String = ""
    @Published public var currentSlug: String = ""
    @Published public var currentChannelInfo: ChannelInfo? = nil
    @Published public var channelNotice: String? = nil
    @Published public var isLoadingChannel: Bool = false
    @Published public var selectedQuality: StreamQuality = .auto {
        didSet {
            applyStreamQuality(selectedQuality)
        }
    }
    @Published public var backgroundEcoModeEnabled: Bool = true
    @Published public var isVideoRenderingActive: Bool = true
    @Published public var volume: Double = 80.0 {
        didSet {
            controller.setVolume(volume)
        }
    }
    @Published public var isMuted: Bool = false {
        didSet {
            controller.setMuted(isMuted)
        }
    }
    @Published public var timePosition: Double = 0.0

    public let controller: MPVController
    private let channelAPI: ChannelResolving
    private var cancellables = Set<AnyCancellable>()

    public init(
        controller: MPVController = MPVController(),
        channelAPI: ChannelResolving = KickChannelAPI()
    ) {
        self.controller = controller
        self.channelAPI = channelAPI
        setupBindings()
        setupOcclusionObservers()
    }

    private func setupBindings() {
        controller.onStateChanged = { [weak self] newState in
            DispatchQueue.main.async {
                self?.state = newState
                AppLogger.shared.info(category: .player, "Oynatıcı durumu: \(newState)")
            }
        }

        controller.onTimePosChanged = { [weak self] time in
            DispatchQueue.main.async {
                self?.timePosition = time
            }
        }
    }

    private func setupOcclusionObservers() {
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)
            .compactMap { $0.object as? NSWindow }
            .sink { [weak self] window in
                self?.handleWindowOcclusion(window)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)
            .sink { [weak self] _ in
                self?.setEcoRendering(enabled: false, reason: "Pencere simge durumuna küçültüldü")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)
            .sink { [weak self] _ in
                self?.setEcoRendering(enabled: true, reason: "Pencere geri açıldı")
            }
            .store(in: &cancellables)
    }

    private func handleWindowOcclusion(_ window: NSWindow) {
        guard backgroundEcoModeEnabled else { return }
        let isVisible = window.occlusionState.contains(.visible)
        setEcoRendering(enabled: isVisible, reason: isVisible ? "Pencere görünür oldu" : "Pencere tamamen gizlendi/arkada kaldı")
    }

    public func setEcoRendering(enabled: Bool, reason: String) {
        guard backgroundEcoModeEnabled else { return }
        guard isVideoRenderingActive != enabled else { return }
        isVideoRenderingActive = enabled
        controller.setVideoRenderingEnabled(enabled)
        AppLogger.shared.info(category: .system, "[Arka Plan Eko Modu] \(reason). Video render: \(enabled ? "Açık" : "Kapalı (GPU tasarrufu)")")
    }

    public func applyStreamQuality(_ quality: StreamQuality) {
        AppLogger.shared.info(category: .player, "Yayın kalitesi değiştiriliyor: \(quality.rawValue)")
        if let bitrate = quality.maxBitrate {
            controller.executeUserCommand("set hls-bitrate \(bitrate)")
        }
    }

    public func load(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentURL = trimmed
        channelNotice = nil
        controller.loadFile(url: trimmed)
    }

    @MainActor
    public func loadChannel(slug: String) async {
        let cleanSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanSlug.isEmpty else { return }

        currentSlug = cleanSlug
        isLoadingChannel = true
        channelNotice = nil

        do {
            let info = try await channelAPI.resolveChannel(slug: cleanSlug)
            self.currentChannelInfo = info
            self.isLoadingChannel = false

            // Son izlenen kanalı kaydet
            UserDefaults.standard.set(cleanSlug, forKey: "lastWatchedSlug")

            if info.isLive, let streamURL = info.playbackURL, !streamURL.isEmpty {
                self.currentURL = streamURL
                self.channelNotice = nil
                self.controller.loadFile(url: streamURL)
            } else {
                self.controller.stop()
                self.channelNotice = "'\(info.username)' şu anda canlı yayında değil."
            }
        } catch let apiError as ChannelAPIError {
            self.isLoadingChannel = false
            self.channelNotice = apiError.localizedDescription
            self.controller.stop()
        } catch {
            self.isLoadingChannel = false
            self.channelNotice = "Kanal çözümlenirken hata oluştu: \(error.localizedDescription)"
            self.controller.stop()
        }
    }

    public func togglePlayPause() {
        switch state {
        case .playing:
            controller.pause()
        case .paused:
            controller.play()
        case .stopped, .idle:
            if !currentURL.isEmpty {
                controller.loadFile(url: currentURL)
            }
        default:
            break
        }
    }

    public func stop() {
        controller.stop()
    }

    public func toggleMute() {
        isMuted.toggle()
    }
}
