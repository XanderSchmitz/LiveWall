import AppKit
import SwiftUI

@main
enum LiveWallMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar app, no Dock icon
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var galleryWindow: NSWindow?
    private var keepAliveActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opt the whole process out of App Nap / idle throttling. Without this, macOS
        // can throttle background accessory apps once they're not frontmost and playing
        // no audio, which stalls video playback instead of letting it loop continuously.
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "LiveWall live wallpaper playback"
        )

        setUpStatusItem()
        WallpaperEngine.shared.start()
        PowerMonitor.shared.start()

        // Pre-warm thumbnails
        for wp in Library.shared.wallpapers {
            _ = Thumbnailer.shared.thumbnail(for: wp)
        }

        // Show the gallery on first launch (no wallpapers yet)
        if Library.shared.wallpapers.isEmpty {
            showGallery()
        }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles.tv",
                                   accessibilityDescription: "LiveWall")
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let gallery = NSMenuItem(title: "Open Gallery…", action: #selector(showGalleryAction), keyEquivalent: "g")
        gallery.target = self
        menu.addItem(gallery)

        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        pause.tag = 100
        menu.addItem(pause)

        let next = NSMenuItem(title: "Next Wallpaper", action: #selector(nextWallpaper), keyEquivalent: "n")
        next.target = self
        menu.addItem(next)

        let shuffle = NSMenuItem(title: "Random Wallpaper", action: #selector(randomWallpaper), keyEquivalent: "")
        shuffle.target = self
        menu.addItem(shuffle)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit LiveWall", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    @objc private func showGalleryAction() { showGallery() }
    @objc private func togglePause() { WallpaperEngine.shared.togglePause() }
    @objc private func nextWallpaper() { WallpaperEngine.shared.nextWallpaper() }
    @objc private func randomWallpaper() { WallpaperEngine.shared.nextWallpaper(random: true) }

    // MARK: Gallery window

    func showGallery() {
        if let window = galleryWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: GalleryView())
        window.title = "LiveWall"
        galleryWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let pauseItem = menu.item(withTag: 100) {
            pauseItem.title = WallpaperEngine.shared.isPaused ? "Resume" : "Pause"
        }
    }
}
