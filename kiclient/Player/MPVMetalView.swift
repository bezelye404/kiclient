import SwiftUI
import AppKit
import QuartzCore
import OpenGL.GL3

public struct MPVMetalView: NSViewRepresentable {
    public typealias NSViewType = NSView

    private let controller: MPVControlling

    public init(controller: MPVControlling) {
        self.controller = controller
    }

    public func makeNSView(context: Context) -> NSView {
        let container = MPVVideoContainerView()
        container.autoresizingMask = [.width, .height]
        container.setup(controller: controller)
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
    }
}

public final class MPVVideoLayer: CAOpenGLLayer {
    public weak var controller: MPVController?
    public private(set) var cglPixelFormat: CGLPixelFormatObj?
    public private(set) var cglContext: CGLContextObj?

    public init(controller: MPVController) {
        self.controller = controller
        super.init()

        var attrs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile,
            CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            CGLPixelFormatAttribute(0)
        ]
        var pix: CGLPixelFormatObj?
        var numPix: GLint = 0
        CGLChoosePixelFormat(&attrs, &pix, &numPix)
        self.cglPixelFormat = pix

        if let pix = pix {
            var ctx: CGLContextObj?
            CGLCreateContext(pix, nil, &ctx)
            self.cglContext = ctx
        }

        self.isAsynchronous = false
        self.needsDisplayOnBoundsChange = true
        self.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    }

    public override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let ctx = cglContext {
            CGLReleaseContext(ctx)
        }
        if let pix = cglPixelFormat {
            CGLReleasePixelFormat(pix)
        }
    }

    public override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        return cglPixelFormat ?? super.copyCGLPixelFormat(forDisplayMask: mask)
    }

    public override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        return cglContext ?? super.copyCGLContext(forPixelFormat: pf)
    }

    public override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        return true
    }

    public override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        if let controller = controller {
            controller.renderFrame(in: ctx, bounds: bounds)
        } else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
        super.draw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: t, displayTime: ts)
    }
}

public final class MPVVideoContainerView: NSView {
    public private(set) var videoLayer: MPVVideoLayer?

    override public var isOpaque: Bool {
        return true
    }

    public func setup(controller: MPVControlling) {
        wantsLayer = true
        if let mpvCtrl = controller as? MPVController {
            let layer = MPVVideoLayer(controller: mpvCtrl)
            self.videoLayer = layer
            self.layer = layer
            mpvCtrl.attach(to: self)
        } else {
            self.layer?.backgroundColor = NSColor.black.cgColor
            controller.attach(to: self)
        }
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window = window {
            layer?.contentsScale = window.backingScaleFactor
        }
    }
}
