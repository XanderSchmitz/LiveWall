import AppKit
import SwiftUI
import AVFoundation
import Darwin

/// Measures LiveWall's own resource usage — real, sampled numbers (not a marketing claim).
final class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()

    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var memoryMB: Double = 0

    private var timer: Timer?
    private var lastCPUTime: Double = 0
    private var lastSampleDate = Date()

    private init() {}

    func start() {
        lastCPUTime = Self.currentCPUTimeSeconds()
        lastSampleDate = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sample()
        }
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let now = Date()
        let nowCPU = Self.currentCPUTimeSeconds()
        let elapsedWall = now.timeIntervalSince(lastSampleDate)
        if elapsedWall > 0 {
            cpuPercent = max(0, min(100, (nowCPU - lastCPUTime) / elapsedWall * 100))
        }
        lastCPUTime = nowCPU
        lastSampleDate = now
        memoryMB = Self.memoryFootprintMB()
    }

    private static func currentCPUTimeSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let sys = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + sys
    }

    private static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1024 / 1024
    }
}

// MARK: - Floating HUD window

final class PerformanceHUDController {
    static let shared = PerformanceHUDController()
    private var panel: NSPanel?

    private init() {}

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func show() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 190, height: 84),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.contentView = NSHostingView(rootView: PerformanceHUDView())
            panel = p
        }
        if let screen = NSScreen.main, let panel {
            let margin: CGFloat = 16
            let origin = NSPoint(
                x: screen.visibleFrame.maxX - panel.frame.width - margin,
                y: screen.visibleFrame.maxY - panel.frame.height - margin)
            panel.setFrameOrigin(origin)
        }
        panel?.orderFrontRegardless()
        PerformanceMonitor.shared.start()
    }
}

private struct PerformanceHUDView: View {
    @ObservedObject var monitor = PerformanceMonitor.shared
    @ObservedObject var engine = WallpaperEngine.shared
    @ObservedObject var library = Library.shared

    private var resolutionText: String {
        guard let wp = library.wallpaper(id: library.settings.activeWallpaperID) else { return "—" }
        if wp.isGIF { return "GIF" }
        let asset = AVURLAsset(url: wp.url)
        guard let track = asset.tracks(withMediaType: .video).first else { return "Video" }
        let size = track.naturalSize.applying(track.preferredTransform)
        return "\(Int(abs(size.width)))×\(Int(abs(size.height)))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVEWALL").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            row("CPU", String(format: "%.1f%%", monitor.cpuPercent))
            row("Memory", String(format: "%.0f MB", monitor.memoryMB))
            row("Resolution", resolutionText)
        }
        .padding(12)
        .frame(width: 190, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit().weight(.medium))
        }
    }
}
