import AppKit
import IOKit.ps

/// Watches battery state and fullscreen apps; auto-pauses playback to save power.
final class PowerMonitor {
    static let shared = PowerMonitor()

    private var timer: Timer?
    private var library: Library { .shared }
    private var engine: WallpaperEngine { .shared }

    private init() {}

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        evaluate()
    }

    private func evaluate() {
        let settings = library.settings
        var shouldPause = false

        if settings.pauseOnBattery && Self.isOnBattery() {
            shouldPause = true
        }
        if !shouldPause && settings.pauseWhenCovered && Self.desktopIsCovered() {
            shouldPause = true
        }

        if shouldPause {
            if !engine.isPaused { engine.pause() }
        } else {
            // Only auto-resume if we were the ones who paused it
            if engine.isPaused && engine.pausedByPolicy { engine.resume(manual: true) }
        }
    }

    static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        for source in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
               let state = info[kIOPSPowerSourceStateKey] as? String {
                return state == kIOPSBatteryPowerValue
            }
        }
        return false
    }

    /// Heuristic: true if a normal app window fully covers a screen (fullscreen app in front).
    static func desktopIsCovered() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let screenFrames = NSScreen.screens.map { frame -> CGRect in
            // CGWindowList uses top-left origin; flip from AppKit coords
            let primaryHeight = NSScreen.screens[0].frame.maxY
            return CGRect(x: frame.origin.x,
                          y: primaryHeight - frame.maxY,
                          width: frame.width,
                          height: frame.height)
        }

        for win in windows {
            guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = win[kCGWindowOwnerPID as String] as? Int32, pid != myPID,
                  let boundsDict = win[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            let bounds = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
            for frame in screenFrames where bounds.contains(frame.insetBy(dx: 1, dy: 1)) {
                return true
            }
        }
        return false
    }
}
