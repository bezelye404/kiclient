import Foundation
import AppKit

public protocol ImageCaching: AnyObject, Sendable {
    func image(for url: URL) -> NSImage?
    func setImage(_ image: NSImage, for url: URL, cost: Int)
    func removeImage(for url: URL)
    func clear()
    func loadImage(from url: URL) async -> NSImage?
}

public final class ImageCacheManager: ImageCaching, @unchecked Sendable {
    public static let shared = ImageCacheManager()

    private let cache = NSCache<NSURL, NSImage>()
    private let session: URLSession

    public init(
        totalCostLimitMB: Int = 30,
        countLimit: Int = 200,
        session: URLSession = .shared
    ) {
        self.session = session
        cache.totalCostLimit = totalCostLimitMB * 1024 * 1024
        cache.countLimit = countLimit

        setupMemoryPressureMonitoring()
    }

    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            self?.clear()
            AppLogger.shared.warning(category: .system, "macOS bellek baskısı algılandı: ImageCache temizlendi.")
        }
        source.resume()
    }

    public func image(for url: URL) -> NSImage? {
        return cache.object(forKey: url as NSURL)
    }

    public func setImage(_ image: NSImage, for url: URL, cost: Int = 0) {
        let calculatedCost = cost > 0 ? cost : Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: calculatedCost)
    }

    public func removeImage(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    public func clear() {
        cache.removeAllObjects()
    }

    public func loadImage(from url: URL) async -> NSImage? {
        if let cached = image(for: url) {
            return cached
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let img = NSImage(data: data) else {
                return nil
            }
            setImage(img, for: url, cost: data.count)
            return img
        } catch {
            return nil
        }
    }
}
