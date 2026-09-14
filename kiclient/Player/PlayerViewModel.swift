import Foundation
import Combine

public final class PlayerViewModel: ObservableObject {
    @Published public var state: MPVPlaybackState = .idle
    @Published public var currentURL: String = ""
    @Published public var currentSlug: String = ""
    @Published public var currentChannelInfo: ChannelInfo? = nil
    @Published public var channelNotice: String? = nil
    @Published public var isLoadingChannel: Bool = false
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

    public init(
        controller: MPVController = MPVController(),
        channelAPI: ChannelResolving = KickChannelAPI()
    ) {
        self.controller = controller
        self.channelAPI = channelAPI
        setupBindings()
    }

    private func setupBindings() {
        controller.onStateChanged = { [weak self] newState in
            DispatchQueue.main.async {
                self?.state = newState
            }
        }

        controller.onTimePosChanged = { [weak self] time in
            DispatchQueue.main.async {
                self?.timePosition = time
            }
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
