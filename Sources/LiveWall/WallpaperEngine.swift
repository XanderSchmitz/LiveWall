import AppKit
import AVFoundation
import ImageIO

// MARK: - Desktop-level window

final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: true)
    }
}

// MARK: - Per-screen renderer

final class ScreenRenderer {
    let window: WallpaperWindow
    let screenKey: String
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var gifLayer: CALayer?
    private var loopObserver: NSObjectProtocol?
    private(set) var current: Wallpaper?

    init(screen: NSScreen) {
        self.screenKey = ScreenRenderer.key(for: screen)
        self.window = WallpaperWindow(screen: screen)
        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = view
        window.orderFront(nil)
    }

    static func key(for screen: NSScreen) -> String {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return id?.stringValue ?? screen.localizedName
    }

    func show(_ wallpaper: Wallpaper, settings: Settings) {
        guard wallpaper != current else {
            applySettings(settings)
            return
        }
        clear()
        current = wallpaper
        if wallpaper.isGIF {
            showGIF(wallpaper)
        } else {
            showVideo(wallpaper, settings: settings)
        }
        applySettings(settings)
    }

    private func showVideo(_ wallpaper: Wallpaper, settings: Settings) {
        let item = AVPlayerItem(url: wallpaper.url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = settings.muted
        avPlayer.actionAtItemEnd = .none          // don't let it stop at the end — we loop manually
        avPlayer.automaticallyWaitsToMinimizeStalling = false

        // Manual seek-to-zero loop: more reliable for a single always-looping item
        // than AVQueuePlayer/AVPlayerLooper, which can silently fail to re-queue.
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                avPlayer?.play()
            }
        }

        let layer = AVPlayerLayer(player: avPlayer)
        layer.frame = window.contentView?.bounds ?? .zero
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        window.contentView?.layer?.addSublayer(layer)

        player = avPlayer
        playerLayer = layer
        avPlayer.play()
    }

    private func showGIF(_ wallpaper: Wallpaper) {
        guard let animation = GIFDecoder.animation(for: wallpaper.url) else { return }
        let layer = CALayer()
        layer.frame = window.contentView?.bounds ?? .zero
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.add(animation, forKey: "gif")
        window.contentView?.layer?.addSublayer(layer)
        gifLayer = layer
    }

    func applySettings(_ settings: Settings) {
        player?.isMuted = settings.muted
        let gravity: CALayerContentsGravity
        let videoGravity: AVLayerVideoGravity
        switch settings.scaling {
        case .fill:    gravity = .resizeAspectFill; videoGravity = .resizeAspectFill
        case .fit:     gravity = .resizeAspect;     videoGravity = .resizeAspect
        case .stretch: gravity = .resize;           videoGravity = .resize
        }
        playerLayer?.videoGravity = videoGravity
        gifLayer?.contentsGravity = gravity
        gifLayer?.masksToBounds = true
    }

    func pause() {
        player?.pause()
        gifLayer?.speed = 0
    }

    func resume() {
        player?.play()
        gifLayer?.speed = 1
    }

    func clear() {
        player?.pause()
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        gifLayer?.removeFromSuperlayer()
        gifLayer = nil
        current = nil
    }

    func tearDown() {
        clear()
        window.orderOut(nil)
    }
}

// MARK: - GIF decoding (ImageIO -> CAKeyframeAnimation)

enum GIFDecoder {
    static func animation(for url: URL) -> CAKeyframeAnimation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var images: [CGImage] = []
        var delays: [Double] = []
        for i in 0..<count {
            guard let img = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(img)
            delays.append(frameDelay(source: source, index: i))
        }
        guard !images.isEmpty else { return nil }

        let total = delays.reduce(0, +)
        var keyTimes: [NSNumber] = [0]
        var acc = 0.0
        for d in delays.dropLast() {
            acc += d
            keyTimes.append(NSNumber(value: acc / total))
        }

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.keyTimes = keyTimes
        anim.duration = total
        anim.calculationMode = .discrete
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        return anim
    }

    private static func frameDelay(source: CGImageSource, index: Int) -> Double {
        let defaultDelay = 0.1
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return defaultDelay }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let delay = unclamped ?? clamped ?? defaultDelay
        return delay < 0.011 ? defaultDelay : delay
    }
}

// MARK: - Engine

final class WallpaperEngine: ObservableObject {
    static let shared = WallpaperEngine()

    @Published private(set) var isPaused = false
    private(set) var pausedByPolicy = false   // paused automatically (battery/fullscreen)
    private var renderers: [String: ScreenRenderer] = [:]
    private var shuffleTimer: Timer?

    private var library: Library { .shared }

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func start() {
        rebuildRenderers()
        refresh()
        restartShuffleTimer()
    }

    @objc private func screensChanged() {
        rebuildRenderers()
        refresh()
    }

    private func rebuildRenderers() {
        let screens = NSScreen.screens
        let keys = Set(screens.map(ScreenRenderer.key(for:)))
        // Remove renderers for disconnected screens
        for (key, renderer) in renderers where !keys.contains(key) {
            renderer.tearDown()
            renderers.removeValue(forKey: key)
        }
        // Add renderers for new screens
        for screen in screens {
            let key = ScreenRenderer.key(for: screen)
            if renderers[key] == nil {
                renderers[key] = ScreenRenderer(screen: screen)
            } else {
                renderers[key]?.window.setFrame(screen.frame, display: true)
            }
        }
    }

    /// Re-applies the correct wallpaper to every screen from settings.
    func refresh() {
        let settings = library.settings
        for (key, renderer) in renderers {
            let wallpaper: Wallpaper?
            if settings.mirrorDisplays {
                wallpaper = library.wallpaper(id: settings.activeWallpaperID)
            } else {
                wallpaper = library.wallpaper(id: settings.perScreenWallpaper[key])
                    ?? library.wallpaper(id: settings.activeWallpaperID)
            }
            if let wallpaper {
                renderer.show(wallpaper, settings: settings)
            } else {
                renderer.clear()
            }
        }
        if isPaused { renderers.values.forEach { $0.pause() } }
    }

    // MARK: Selection

    func setWallpaper(_ wallpaper: Wallpaper) {
        library.settings.activeWallpaperID = wallpaper.id
        refresh()
    }

    func setWallpaper(_ wallpaper: Wallpaper, forScreenKey key: String) {
        library.settings.perScreenWallpaper[key] = wallpaper.id
        refresh()
    }

    func nextWallpaper(random: Bool = false) {
        let list = library.wallpapers
        guard !list.isEmpty else { return }
        if random, list.count > 1 {
            var pick = list.randomElement()!
            while pick.id == library.settings.activeWallpaperID, list.count > 1 {
                pick = list.randomElement()!
            }
            setWallpaper(pick)
        } else {
            let idx = list.firstIndex { $0.id == library.settings.activeWallpaperID } ?? -1
            setWallpaper(list[(idx + 1) % list.count])
        }
    }

    // MARK: Pause / resume

    func togglePause() {
        isPaused ? resume(manual: true) : pause(manual: true)
    }

    func pause(manual: Bool = false) {
        if !manual { pausedByPolicy = true }
        isPaused = true
        renderers.values.forEach { $0.pause() }
    }

    func resume(manual: Bool = false) {
        if manual { pausedByPolicy = false }
        isPaused = false
        renderers.values.forEach { $0.resume() }
    }

    // MARK: Shuffle

    func restartShuffleTimer() {
        shuffleTimer?.invalidate()
        shuffleTimer = nil
        let settings = library.settings
        guard settings.shuffleEnabled, settings.shuffleMinutes > 0 else { return }
        shuffleTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(settings.shuffleMinutes * 60),
            repeats: true
        ) { [weak self] _ in
            self?.nextWallpaper(random: true)
        }
    }

    var screenKeys: [(key: String, name: String)] {
        NSScreen.screens.map { (ScreenRenderer.key(for: $0), $0.localizedName) }
    }
}
