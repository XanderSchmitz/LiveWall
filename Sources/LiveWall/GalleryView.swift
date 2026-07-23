import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

// MARK: - Gallery window content

struct GalleryView: View {
    @ObservedObject var library = Library.shared
    @ObservedObject var engine = WallpaperEngine.shared
    @ObservedObject var thumbs = Thumbnailer.shared
    @State private var isDropTargeted = false
    @State private var showingSettings = false

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    var body: some View {
        ZStack {
            VisualEffectBackground()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                if library.wallpapers.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            if isDropTargeted { dropOverlay }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles.tv.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("LiveWall")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Spacer()

            Button {
                engine.togglePause()
            } label: {
                Label(engine.isPaused ? "Resume" : "Pause",
                      systemImage: engine.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            .disabled(library.settings.activeWallpaperID == nil)

            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(.bordered)

            Button(action: pickFiles) {
                Label("Add Wallpapers", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding(16)
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(library.wallpapers) { wp in
                    WallpaperCard(
                        wallpaper: wp,
                        isActive: library.settings.activeWallpaperID == wp.id,
                        thumbnail: thumbs.thumbnail(for: wp)
                    )
                }
            }
            .padding(16)
        }
    }

    // MARK: Empty / drop states

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No wallpapers yet")
                .font(.title3.weight(.semibold))
            Text("Drop videos or GIFs here, or click “Add Wallpapers”.\nSupports MP4, MOV, M4V, HEVC/6K, WebM*, MKV*, AVI* and GIF.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("*Formats not natively supported by macOS may need conversion.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding()
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10]))
            .foregroundStyle(.purple)
            .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                Label("Drop to add", systemImage: "arrow.down.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.purple)
            }
            .padding(12)
            .allowsHitTesting(false)
    }

    // MARK: Actions

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .gif, .avi]
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls { library.importFile(at: url) }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let url { _ = library.importFile(at: url) }
            }
        }
        return true
    }
}

// MARK: - Card

struct WallpaperCard: View {
    let wallpaper: Wallpaper
    let isActive: Bool
    let thumbnail: NSImage?
    @ObservedObject var engine = WallpaperEngine.shared
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay { ProgressView().controlSize(.small) }
                    }
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if hovering {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.35))
                    Button {
                        engine.setWallpaper(wallpaper)
                    } label: {
                        Label(isActive ? "Active" : "Set Wallpaper",
                              systemImage: isActive ? "checkmark.circle.fill" : "play.circle.fill")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }

                if isActive {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .purple)
                                .shadow(radius: 3)
                                .padding(8)
                        }
                        Spacer()
                    }
                }

                if wallpaper.isGIF {
                    VStack {
                        Spacer()
                        HStack {
                            Text("GIF")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(6)
                            Spacer()
                        }
                    }
                }
            }
            .frame(height: 140)

            HStack {
                Text(wallpaper.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Menu {
                    Section("Set on display") {
                        ForEach(engine.screenKeys, id: \.key) { screen in
                            Button(screen.name) {
                                Library.shared.settings.mirrorDisplays = false
                                engine.setWallpaper(wallpaper, forScreenKey: screen.key)
                            }
                        }
                    }
                    Divider()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([wallpaper.url])
                    }
                    Button("Remove", role: .destructive) {
                        Library.shared.remove(wallpaper)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isActive ? Color.purple.opacity(0.7) : Color.white.opacity(0.08),
                              lineWidth: isActive ? 2 : 1)
        }
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var library = Library.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            }
            .padding(16)
            Divider()

            Form {
                Section("Playback") {
                    Toggle("Mute audio", isOn: binding(\.muted))
                    Picker("Scaling", selection: binding(\.scaling)) {
                        ForEach(ScalingMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Same wallpaper on all displays", isOn: binding(\.mirrorDisplays))
                }
                Section("Shuffle") {
                    Toggle("Shuffle wallpapers", isOn: binding(\.shuffleEnabled))
                    if library.settings.shuffleEnabled {
                        Stepper("Every \(library.settings.shuffleMinutes) min",
                                value: binding(\.shuffleMinutes), in: 1...480, step: 5)
                    }
                }
                Section("Power") {
                    Toggle("Pause on battery", isOn: binding(\.pauseOnBattery))
                    Toggle("Pause when a fullscreen app is in front", isOn: binding(\.pauseWhenCovered))
                }
                Section("General") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { library.settings.launchAtLogin },
                        set: { newValue in
                            library.settings.launchAtLogin = newValue
                            LoginItem.set(enabled: newValue)
                        }))
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420, height: 440)
        .onChange(of: library.settings.shuffleEnabled) { _ in
            WallpaperEngine.shared.restartShuffleTimer()
        }
        .onChange(of: library.settings.shuffleMinutes) { _ in
            WallpaperEngine.shared.restartShuffleTimer()
        }
        .onChange(of: library.settings.muted) { _ in WallpaperEngine.shared.refresh() }
        .onChange(of: library.settings.scaling) { _ in WallpaperEngine.shared.refresh() }
        .onChange(of: library.settings.mirrorDisplays) { _ in WallpaperEngine.shared.refresh() }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { library.settings[keyPath: keyPath] },
            set: { library.settings[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - Login item helper

enum LoginItem {
    static func set(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LiveWall: launch-at-login change failed — \(error.localizedDescription)")
        }
    }
}

// MARK: - Blur background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
