import Foundation
import AppKit

// MARK: - Wallpaper model

struct Wallpaper: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var path: String          // absolute path to the media file
    var isGIF: Bool

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
    var pauseOnBattery: Bool = false
    var pauseWhenCovered: Bool = true
    var launchAtLogin: Bool = false
    var mirrorDisplays: Bool = true                 // same wallpaper on all screens
    var activeWallpaperID: UUID? = nil              // when mirroring
    var perScreenWallpaper: [String: UUID] = [:]    // screen key -> wallpaper id
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
    func importFile(at url: URL) -> Wallpaper? {
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
            try fm.copyItem(at: url, to: dest)
        } catch {
            NSLog("LiveWall: import failed — \(error.localizedDescription)")
            return nil
        }
        let wp = Wallpaper(url: dest)
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

    func wallpaper(id: UUID?) -> Wallpaper? {
        guard let id else { return nil }
        return wallpapers.first { $0.id == id }
    }
}
