import SwiftUI
import AppKit

public struct MPVMetalView: NSViewRepresentable {
    public typealias NSViewType = NSView

    private let controller: MPVControlling

    public init(controller: MPVControlling) {
        self.controller = controller
    }

    public func makeNSView(context: Context) -> NSView {
        let view = MPVVideoContainerView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.autoresizingMask = [.width, .height]

        controller.attach(to: view)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // View boyutu değiştiğinde mpv layer'ı otomatik uyum sağlar
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // View kaldırıldığında kaynakları temizle
    }
}

final class MPVVideoContainerView: NSView {
    override var isOpaque: Bool {
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
}
