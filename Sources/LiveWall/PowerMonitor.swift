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
            // Respect a manual Resume: don't re-pause until the condition clears once
            if !engine.isPaused && !engine.policyOverridden { engine.pause() }
        } else {
            engine.clearPolicyOverride()
            // Only auto-resume if we were the ones who paused it
            if engine.isPaused && engine.pausedByPolicy { engine.resume() }
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

    /// Heuristic: true only if the FRONTMOST (focused) app has a window fully covering a screen.
    /// Only the frontmost app's windows count — a maximized window sitting in the background
    /// must not trigger a pause, since it isn't actually hiding the desktop from the user.
    static func desktopIsCovered() -> Bool {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontPID != ProcessInfo.processInfo.processIdentifier
        else { return false }

        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let screenFrames = NSScreen.screens.map { screen -> CGRect in
            // CGWindowList uses top-left origin; flip from AppKit coords
            let primaryHeight = NSScreen.screens[0].frame.maxY
            let frame = screen.frame
            return CGRect(x: frame.origin.x,
                          y: primaryHeight - frame.maxY,
                          width: frame.width,
                          height: frame.height)
        }

        for win in windows {
            guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = win[kCGWindowOwnerPID as String] as? Int32, pid == frontPID,
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
