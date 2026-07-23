import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Generates and caches PNG thumbnails for wallpapers.
final class Thumbnailer: ObservableObject {
    static let shared = Thumbnailer()

    @Published private(set) var cache: [UUID: NSImage] = [:]
    private let queue = DispatchQueue(label: "livewall.thumbs", qos: .utility)

    private init() {}

    func thumbnail(for wallpaper: Wallpaper) -> NSImage? {
        if let img = cache[wallpaper.id] { return img }
        let file = Library.shared.thumbsDir
            .appendingPathComponent("\(wallpaper.id.uuidString).png")
        if let img = NSImage(contentsOf: file) {
            DispatchQueue.main.async { self.cache[wallpaper.id] = img }
            return img
        }
        generate(for: wallpaper)
        return nil
    }

    func generate(for wallpaper: Wallpaper) {
        queue.async { [weak self] in
            guard let self else { return }
            let cgImage: CGImage?
            if wallpaper.isGIF {
                cgImage = Self.gifFirstFrame(url: wallpaper.url)
            } else {
                cgImage = Self.videoFrame(url: wallpaper.url)
            }
            guard let cgImage else { return }

            let image = NSImage(cgImage: cgImage, size: .zero)
            let file = Library.shared.thumbsDir
                .appendingPathComponent("\(wallpaper.id.uuidString).png")
            Self.writePNG(cgImage, to: file)
            DispatchQueue.main.async { self.cache[wallpaper.id] = image }
        }
    }

    private static func videoFrame(url: URL) -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        return (try? generator.copyCGImage(at: time, actualTime: nil))
            ?? (try? generator.copyCGImage(at: .zero, actualTime: nil))
    }

    private static func gifFirstFrame(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 640
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
