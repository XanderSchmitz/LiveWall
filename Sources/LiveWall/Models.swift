import Foundation
import AppKit

// MARK: - Wallpaper model

struct Wallpaper: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var path: String          // absolute path to the media file
    var isGIF: Bool
    var tags: [String] = []
    var volume: Double = 1.0          // 0...1, applied on top of the global mute
    var muteOverride: Bool? = nil     // nil = follow global mute setting
    var dimOpacity: Double = 0        // 0...1 black overlay, so busy video doesn't fight desktop icons
    var blurRadius: Double = 0        // 0...40 Gaussian blur, macOS-Tahoe-style frosted background

    var url: URL { URL(fileURLWithPath: path) }

    init(url: URL) {
        self.id = UUID()
        self.name = url.deletingPathExtension().lastPathComponent
        self.path = url.path
        self.isGIF = url.pathExtension.lowercased() == "gif"
    }
}

// MARK: - Settings

enum ScalingMode: String, Codable, CaseIterable, Identifiable {
    case fill = "Fill"
    case fit = "Fit"
    case stretch = "Stretch"
    var id: String { rawValue }
}

struct Settings: Codable {
    var muted: Bool = true
    var scaling: ScalingMode = .fill
    var shuffleEnabled: Bool = false
    var shuffleMinutes: Int = 30
    var shuffleTag: String? = nil                   // nil = shuffle across the whole library
    var pauseOnBattery: Bool = false
    var pauseWhenCovered: Bool = true
    var launchAtLogin: Bool = false
    var mirrorDisplays: Bool = true                 // same wallpaper on all screens
    var activeWallpaperID: UUID? = nil              // when mirroring
    var perScreenWallpaper: [String: UUID] = [:]    // screen key -> wallpaper id
    var globalHotkeysEnabled: Bool = false
    var showPerformanceHUD: Bool = false
}

// MARK: - Library (persistence)

final class Library: ObservableObject {
    static let shared = Library()

    @Published var wallpapers: [Wallpaper] = []
    @Published var settings = Settings() {
        didSet { save() }
    }

    static let supportedVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "ts", "m2ts", "3gp", "hevc"
    ]
    static let supportedExtensions: Set<String> = supportedVideoExtensions.union(["gif"])

    private let fm = FileManager.default

    var appSupportDir: URL {
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveWall", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var mediaDir: URL {
        let dir = appSupportDir.appendingPathComponent("Media", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var thumbsDir: URL {
        let dir = appSupportDir.appendingPathComponent("Thumbnails", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var stateFile: URL { appSupportDir.appendingPathComponent("library.json") }

    private struct State: Codable {
        var wallpapers: [Wallpaper]
        var settings: Settings
    }

    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: stateFile),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return }
        wallpapers = state.wallpapers.filter { fm.fileExists(atPath: $0.path) }
        settings = state.settings
    }

    func save() {
        let state = State(wallpapers: wallpapers, settings: settings)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFile, options: .atomic)
        }
    }

    /// Import a media file: copies it into the app's media folder.
    @discardableResult
    func importFile(at url: URL, tags: [String] = []) -> Wallpaper? {
        let ext = url.pathExtension.lowercased()
        guard Library.supportedExtensions.contains(ext) else { return nil }

        var dest = mediaDir.appendingPathComponent(url.lastPathComponent)
        // Avoid name collisions
        var counter = 1
        while fm.fileExists(atPath: dest.path) {
            let base = url.deletingPathExtension().lastPathComponent
            dest = mediaDir.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: url, to: dest)
        } catch {
            NSLog("LiveWall: import failed — \(error.localizedDescription)")
            return nil
        }
        var wp = Wallpaper(url: dest)
        wp.tags = tags
        DispatchQueue.main.async {
            self.wallpapers.append(wp)
            self.save()
            Thumbnailer.shared.generate(for: wp)
        }
        return wp
    }

    func remove(_ wallpaper: Wallpaper) {
        wallpapers.removeAll { $0.id == wallpaper.id }
        try? fm.removeItem(at: wallpaper.url)
        try? fm.removeItem(at: thumbsDir.appendingPathComponent("\(wallpaper.id.uuidString).png"))
        if settings.activeWallpaperID == wallpaper.id { settings.activeWallpaperID = nil }
        for (k, v) in settings.perScreenWallpaper where v == wallpaper.id {
            settings.perScreenWallpaper.removeValue(forKey: k)
        }
        save()
        WallpaperEngine.shared.refresh()
    }

    func update(_ wallpaper: Wallpaper) {
        guard let idx = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        wallpapers[idx] = wallpaper
        save()
        WallpaperEngine.shared.refresh()
    }

    func wallpaper(id: UUID?) -> Wallpaper? {
        guard let id else { return nil }
        return wallpapers.first { $0.id == id }
    }

    // MARK: Tags / playlists

    var allTags: [String] {
        Array(Set(wallpapers.flatMap(\.tags))).sorted()
    }

    func wallpapers(taggedWith tag: String?) -> [Wallpaper] {
        guard let tag else { return wallpapers }
        return wallpapers.filter { $0.tags.contains(tag) }
    }

    /// Import a media file downloaded from a URL (e.g. a Pexels/Coverr link).
    func importFromURL(_ remoteURL: URL, tags: [String] = [], completion: @escaping (Wallpaper?) -> Void) {
        let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tmpURL, response, error in
            guard let self, let tmpURL, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Determine an extension: prefer the URL's own, fall back to the response's suggested filename
            var ext = remoteURL.pathExtension.lowercased()
            if !Library.supportedExtensions.contains(ext),
               let suggested = response?.suggestedFilename {
                ext = (suggested as NSString).pathExtension.lowercased()
            }
            guard Library.supportedExtensions.contains(ext) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // downloadTask hands us a temp file with no extension; rename so importFile can validate it
            let renamed = tmpURL.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                try self.fm.moveItem(at: tmpURL, to: renamed)
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let wp = self.importFile(at: renamed, tags: tags)
            try? self.fm.removeItem(at: renamed)
            DispatchQueue.main.async { completion(wp) }
        }
        task.resume()
    }
}
