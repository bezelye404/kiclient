import Foundation
import AppKit
import QuartzCore
import OpenGL.GL3

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
        vo: "libmpv",
        cache: "yes",
        demuxerMaxBytes: "33554432",      // 32 MiB
        demuxerMaxBackBytes: "16777216",  // 16 MiB
        videoSync: "audio",
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
            "audio-pitch-correction": "yes",
            "audio-buffer": "0.2",
            "correct-pts": "yes",
            "hr-seek": "no",
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
    public private(set) var renderContext: OpaquePointer?
    private let eventQueue = DispatchQueue(label: "com.kiclient.mpv.events", qos: .userInitiated)
    private var isRunning = false
    private weak var attachedView: NSView?
    private weak var attachedLayer: CAOpenGLLayer?

    public var hasRenderContext: Bool {
        return renderContext != nil
    }

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
        if let container = view as? MPVVideoContainerView, let layer = container.videoLayer {
            attachVideoLayer(layer)
        }
    }

    public func attachVideoLayer(_ layer: MPVVideoLayer) {
        self.attachedLayer = layer
        guard let handle = self.mpv, let cglContext = layer.cglContext else { return }

        if renderContext != nil {
            return
        }

        CGLSetCurrentContext(cglContext)

        let apiType = strdup(MPV_RENDER_API_TYPE_OPENGL)
        defer { free(apiType) }

        var initParams = mpv_opengl_init_params(
            get_proc_address: { (_, name) -> UnsafeMutableRawPointer? in
                guard let name = name else { return nil }
                let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
                guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString),
                      let addr = CFBundleGetFunctionPointerForName(bundle, symbolName) else {
                    return nil
                }
                return addr
            },
            get_proc_address_ctx: nil
        )

        var advanced: CInt = 1
        var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(apiType)),
            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: &initParams),
            mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: &advanced),
            mpv_render_param()
        ]

        var rCtx: OpaquePointer?
        let err = mpv_render_context_create(&rCtx, handle, &params)
        if err >= 0, let validCtx = rCtx {
            self.renderContext = validCtx
            AppLogger.shared.info(category: .player, "libmpv Render API (OpenGL) başarıyla kuruldu.")

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            mpv_render_context_set_update_callback(validCtx, { ctx in
                guard let ctx = ctx else { return }
                let controller = Unmanaged<MPVController>.fromOpaque(ctx).takeUnretainedValue()
                controller.requestFrameRender()
            }, selfPtr)
        } else {
            let errStr = String(cString: mpv_error_string(err))
            AppLogger.shared.error(category: .player, "mpv_render_context_create hatası: \(errStr)")
        }
    }

    public func requestFrameRender() {
        guard let rCtx = renderContext else { return }
        let flags = mpv_render_context_update(rCtx)
        if (flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue)) != 0 {
            DispatchQueue.main.async { [weak self] in
                self?.attachedLayer?.setNeedsDisplay()
            }
        }
    }

    public private(set) var isVideoRenderingActive: Bool = true

    public func renderFrame(in ctx: CGLContextObj, bounds: CGRect) {
        guard let rCtx = renderContext, isVideoRenderingActive else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }

        CGLSetCurrentContext(ctx)

        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &fbo)

        var viewport: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let w: Int32 = viewport[2] > 0 ? viewport[2] : Int32(max(bounds.width * scale, 1.0))
        let h: Int32 = viewport[3] > 0 ? viewport[3] : Int32(max(bounds.height * scale, 1.0))

        var flip: CInt = 1
        var fboData = mpv_opengl_fbo(
            fbo: fbo,
            w: w,
            h: h,
            internal_format: 0
        )

        var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: &fboData),
            mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: &flip),
            mpv_render_param()
        ]

        mpv_render_context_render(rCtx, &params)
        glFlush()
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
        isVideoRenderingActive = enabled
        if !enabled {
            attachedLayer?.setNeedsDisplay()
        }
        AppLogger.shared.info(category: .player, "Video katman çizimi: \(enabled ? "Aktif" : "Pasif (GPU Tasarrufu)")")
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
        if let rCtx = renderContext {
            mpv_render_context_set_update_callback(rCtx, nil, nil)
            mpv_render_context_free(rCtx)
            renderContext = nil
        }
        if let handle = mpv {
            mpv = nil
            mpv_terminate_destroy(handle)
        }
    }
}
