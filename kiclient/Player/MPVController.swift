import Foundation
import AppKit

public enum MPVPlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(String)
}

public struct MPVConfiguration: Equatable, Sendable {
    public var hwdec: String
    public var vo: String
    public var cache: String
    public var demuxerMaxBytes: String
    public var demuxerMaxBackBytes: String
    public var videoSync: String
    public var frameDrop: String
    public var profile: String

    public static let lowResourceDefault = MPVConfiguration(
        hwdec: "videotoolbox",
        vo: "gpu-next",
        cache: "yes",
        demuxerMaxBytes: "33554432",      // 32 MiB
        demuxerMaxBackBytes: "16777216",  // 16 MiB
        videoSync: "display-resample",
        frameDrop: "vo",
        profile: "low-latency"
    )

    public func optionsDictionary() -> [String: String] {
        return [
            "hwdec": hwdec,
            "vo": vo,
            "cache": cache,
            "demuxer-max-bytes": demuxerMaxBytes,
            "demuxer-max-back-bytes": demuxerMaxBackBytes,
            "video-sync": videoSync,
            "framedrop": frameDrop,
            "profile": profile,
            "input-default-bindings": "no",
            "input-vo-keyboard": "no"
        ]
    }
}

public protocol MPVControlling: AnyObject {
    var state: MPVPlaybackState { get }
    var configuration: MPVConfiguration { get }
    func attach(to view: NSView)
    func loadFile(url: String)
    func play()
    func pause()
    func stop()
    func setVolume(_ volume: Double)
    func setMuted(_ muted: Bool)
    func setVideoRenderingEnabled(_ enabled: Bool)
    func getPropertyString(_ name: String) -> String?
    func executeUserCommand(_ commandLine: String) -> String
}

public final class MPVController: MPVControlling {
    public private(set) var state: MPVPlaybackState = .idle {
        didSet {
            onStateChanged?(state)
        }
    }

    public let configuration: MPVConfiguration
    public var onStateChanged: ((MPVPlaybackState) -> Void)?
    public var onTimePosChanged: ((Double) -> Void)?

    private var mpv: OpaquePointer?
    private let eventQueue = DispatchQueue(label: "com.kiclient.mpv.events", qos: .userInitiated)
    private var isRunning = false
    private weak var attachedView: NSView?

    public init(configuration: MPVConfiguration = .lowResourceDefault) {
        self.configuration = configuration
        setupMPV()
    }

    deinit {
        destroyMPV()
    }

    private func setupMPV() {
        guard let handle = mpv_create() else {
            state = .error("libmpv başlatılamadı (mpv_create başarısız)")
            return
        }
        self.mpv = handle

        // Temel performans ve donanım hızlandırma ayarlarını uygula
        for (key, val) in configuration.optionsDictionary() {
            mpv_set_option_string(handle, key, val)
        }

        // Özellik gözlemleri
        mpv_observe_property(handle, 1, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 2, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 3, "eof-reached", MPV_FORMAT_FLAG)

        // Dahili mpv loglarını AppLogger'a aktar
        mpv_request_log_messages(handle, "info")

        let initStatus = mpv_initialize(handle)
        if initStatus < 0 {
            let errMsg = String(cString: mpv_error_string(initStatus))
            state = .error("mpv_initialize hatası: \(errMsg)")
            return
        }

        startEventLoop()
    }

    public func attach(to view: NSView) {
        self.attachedView = view
        guard let handle = mpv else { return }

        // Host processteki NSView bellek adresini wid olarak ver
        let viewPointer = Int64(bitPattern: UInt64(UInt(bitPattern: Unmanaged.passUnretained(view).toOpaque())))
        var wid = viewPointer
        let err = mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid)
        if err < 0 {
            let errMsg = String(cString: mpv_error_string(err))
            print("[MPVController] wid ayarlanamadı: \(errMsg)")
        }
    }

    @discardableResult
    public func command(_ args: [String]) -> Int32 {
        guard let handle = mpv else { return -1 }
        var cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cStrings.append(nil)
        defer {
            for ptr in cStrings {
                if let ptr = ptr { free(ptr) }
            }
        }
        return cStrings.withUnsafeMutableBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else { return -1 }
            let ptr = UnsafeMutableRawPointer(baseAddress).assumingMemoryBound(to: UnsafePointer<CChar>?.self)
            return mpv_command(handle, ptr)
        }
    }

    public func loadFile(url: String) {
        state = .loading
        let res = command(["loadfile", url])
        if res < 0 {
            let err = String(cString: mpv_error_string(res))
            DispatchQueue.main.async {
                self.state = .error("Yayın yüklenemedi: \(err)")
            }
        }
    }

    public func play() {
        guard let handle = mpv else { return }
        var pauseFlag: Int32 = 0
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &pauseFlag)
        state = .playing
    }

    public func pause() {
        guard let handle = mpv else { return }
        var pauseFlag: Int32 = 1
        mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &pauseFlag)
        state = .paused
    }

    public func stop() {
        command(["stop"])
        state = .stopped
    }

    public func setVolume(_ volume: Double) {
        guard let handle = mpv else { return }
        var vol = min(max(volume, 0.0), 100.0)
        mpv_set_property(handle, "volume", MPV_FORMAT_DOUBLE, &vol)
    }

    public func setMuted(_ muted: Bool) {
        guard let handle = mpv else { return }
        var muteFlag: Int32 = muted ? 1 : 0
        mpv_set_property(handle, "mute", MPV_FORMAT_FLAG, &muteFlag)
    }

    private func startEventLoop() {
        isRunning = true
        eventQueue.async { [weak self] in
            while let self = self, self.isRunning, let handle = self.mpv {
                let eventPtr = mpv_wait_event(handle, 0.1)
                guard let event = eventPtr?.pointee, event.event_id != MPV_EVENT_NONE else {
                    continue
                }
                self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_START_FILE:
            DispatchQueue.main.async {
                self.state = .loading
            }
        case MPV_EVENT_PLAYBACK_RESTART, MPV_EVENT_FILE_LOADED:
            DispatchQueue.main.async {
                self.state = .playing
            }
        case MPV_EVENT_END_FILE:
            DispatchQueue.main.async {
                self.state = .stopped
            }
        case MPV_EVENT_SHUTDOWN:
            DispatchQueue.main.async {
                self.state = .idle
            }
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let prop = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee else { return }
            let propName = String(cString: prop.name)
            if propName == "time-pos", prop.format == MPV_FORMAT_DOUBLE {
                let timePos = prop.data.assumingMemoryBound(to: Double.self).pointee
                DispatchQueue.main.async {
                    self.onTimePosChanged?(timePos)
                }
            } else if propName == "pause", prop.format == MPV_FORMAT_FLAG {
                let isPaused = prop.data.assumingMemoryBound(to: Int32.self).pointee != 0
                DispatchQueue.main.async {
                    if isPaused && self.state == .playing {
                        self.state = .paused
                    } else if !isPaused && self.state == .paused {
                        self.state = .playing
                    }
                }
            }
        case MPV_EVENT_LOG_MESSAGE:
            guard let logMsg = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee else { return }
            let prefix = logMsg.prefix != nil ? String(cString: logMsg.prefix) : "mpv"
            let text = logMsg.text != nil ? String(cString: logMsg.text).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if !text.isEmpty {
                let lvl: LogLevel
                switch logMsg.log_level {
                case MPV_LOG_LEVEL_FATAL, MPV_LOG_LEVEL_ERROR:
                    lvl = .error
                case MPV_LOG_LEVEL_WARN:
                    lvl = .warning
                case MPV_LOG_LEVEL_DEBUG, MPV_LOG_LEVEL_TRACE:
                    lvl = .debug
                default:
                    lvl = .info
                }
                AppLogger.shared.log(lvl, category: .player, "[\(prefix)] \(text)")
            }
        default:
            break
        }
    }

    public func setVideoRenderingEnabled(_ enabled: Bool) {
        guard let handle = mpv else { return }
        let vidVal = enabled ? "auto" : "no"
        mpv_set_property_string(handle, "vid", vidVal)
        AppLogger.shared.info(category: .player, "Video render modu: \(vidVal)")
    }

    public func getPropertyString(_ name: String) -> String? {
        guard let handle = mpv else { return nil }
        guard let cStr = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(cStr) }
        return String(cString: cStr)
    }

    public func executeUserCommand(_ commandLine: String) -> String {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Boş komut." }
        guard let handle = mpv else { return "mpv henüz hazır değil." }

        let parts = trimmed.split(separator: " ").map(String.init)
        if (parts.first == "get_property" || parts.first == "get") && parts.count >= 2 {
            let propName = parts[1]
            if let val = getPropertyString(propName) {
                AppLogger.shared.info(category: .player, "> \(trimmed) => \(val)")
                return "\(propName) = \(val)"
            } else {
                return "\(propName) okunamadı (nil)"
            }
        }

        let res = mpv_command_string(handle, trimmed)
        if res < 0 {
            let errStr = String(cString: mpv_error_string(res))
            AppLogger.shared.error(category: .player, "> \(trimmed) => Hata: \(errStr)")
            return "Hata (\(res)): \(errStr)"
        } else {
            AppLogger.shared.info(category: .player, "> \(trimmed) => Başarılı")
            return "OK"
        }
    }

    private func destroyMPV() {
        isRunning = false
        if let handle = mpv {
            mpv = nil
            mpv_terminate_destroy(handle)
        }
    }
}
