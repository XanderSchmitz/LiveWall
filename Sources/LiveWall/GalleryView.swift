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
    @State private var showingImportURL = false
    @State private var selectedTag: String? = nil
    @State private var editingWallpaper: Wallpaper? = nil

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    private var visibleWallpapers: [Wallpaper] {
        library.wallpapers(taggedWith: selectedTag)
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            HStack(spacing: 0) {
                sidebar
                Divider().opacity(0.3)
                VStack(spacing: 0) {
                    header
                    if visibleWallpapers.isEmpty {
                        emptyState
                    } else {
                        grid
                    }
                }
            }
            if isDropTargeted { dropOverlay }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingImportURL) { ImportURLView() }
        .sheet(item: $editingWallpaper) { wp in WallpaperEditView(wallpaper: wp) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.title3)
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("LiveWall")
                    .font(.system(.title3, design: .rounded).weight(.bold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 18)

            sidebarRow(title: "All Wallpapers", icon: "square.grid.2x2.fill", isSelected: selectedTag == nil) {
                selectedTag = nil
            }

            if !library.allTags.isEmpty {
                Text("PLAYLISTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                ForEach(library.allTags, id: \.self) { tag in
                    sidebarRow(title: tag, icon: "play.square.stack.fill", isSelected: selectedTag == tag) {
                        selectedTag = tag
                    }
                }
            }

            Spacer()

            VStack(spacing: 8) {
                sidebarButton("Import from URL…", icon: "link") { showingImportURL = true }
                sidebarButton("Settings", icon: "gearshape.fill") { showingSettings = true }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .frame(width: 200)
    }

    private func sidebarRow(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 16)
                Text(title).font(.callout.weight(isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.purple.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isSelected ? Color.purple : Color.primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func sidebarButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.callout)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(selectedTag ?? "All Wallpapers")
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

            Button(action: pickFiles) {
                Label("Add Wallpapers", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding(20)
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(visibleWallpapers) { wp in
                    WallpaperCard(
                        wallpaper: wp,
                        isActive: library.settings.activeWallpaperID == wp.id,
                        thumbnail: thumbs.thumbnail(for: wp),
                        onEdit: { editingWallpaper = wp }
                    )
                }
            }
            .padding(20)
        }
    }

    // MARK: Empty / drop states

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text(selectedTag == nil ? "No wallpapers yet" : "No wallpapers tagged “\(selectedTag!)”")
                .font(.title3.weight(.semibold))
            Text("Drop videos or GIFs here, click “Add Wallpapers”, or import from a URL.\nSupports MP4, MOV, M4V, HEVC/6K, WebM*, MKV*, AVI* and GIF.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("*Formats not natively supported by macOS may need conversion.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
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
        panel.allowedContentTypes = Library.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.begin { response in
            guard response == .OK else { return }
            let tags = selectedTag.map { [$0] } ?? []
            for url in panel.urls { library.importFile(at: url, tags: tags) }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let tags = selectedTag.map { [$0] } ?? []
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let url { _ = library.importFile(at: url, tags: tags) }
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
    let onEdit: () -> Void
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

                VStack {
                    Spacer()
                    HStack {
                        if wallpaper.isGIF {
                            badge("GIF")
                        }
                        if wallpaper.blurRadius > 0 {
                            badge("Blurred", icon: "drop.fill")
                        }
                        if wallpaper.dimOpacity > 0 {
                            badge("Dimmed", icon: "moon.fill")
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .frame(height: 140)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(wallpaper.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if !wallpaper.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(wallpaper.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                }
                Spacer()
                Menu {
                    Button("Edit…") { onEdit() }
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
        .onTapGesture(count: 2) { onEdit() }
    }

    private func badge(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 8)) }
            Text(text).font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Per-wallpaper edit sheet

struct WallpaperEditView: View {
    @State var wallpaper: Wallpaper
    @Environment(\.dismiss) private var dismiss
    @State private var newTag: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(wallpaper.name)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(1)
                Spacer()
                Button("Done") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Playlists / Tags").font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    ForEach(wallpaper.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag).font(.caption.weight(.semibold))
                            Button { wallpaper.tags.removeAll { $0 == tag } } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(.purple)
                    }
                }
                HStack {
                    TextField("New tag…", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTag)
                    Button("Add", action: addTag).disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !wallpaper.isGIF {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Volume").font(.subheadline.weight(.semibold))
                    HStack {
                        Slider(value: $wallpaper.volume, in: 0...1)
                        Text("\(Int(wallpaper.volume * 100))%").font(.caption).frame(width: 40)
                    }
                    Toggle("Always mute this wallpaper", isOn: Binding(
                        get: { wallpaper.muteOverride == true },
                        set: { wallpaper.muteOverride = $0 ? true : nil }))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Dim overlay").font(.subheadline.weight(.semibold))
                Text("Darkens the wallpaper so busy video doesn't fight your desktop icons.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Slider(value: $wallpaper.dimOpacity, in: 0...0.85)
                    Text("\(Int(wallpaper.dimOpacity * 100))%").font(.caption).frame(width: 40)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Blur").font(.subheadline.weight(.semibold))
                Text("Frosted-glass background blur, like macOS's own wallpaper blur.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Slider(value: $wallpaper.blurRadius, in: 0...40)
                    Text("\(Int(wallpaper.blurRadius))").font(.caption).frame(width: 40)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 380, height: 480)
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !wallpaper.tags.contains(t) else { return }
        wallpaper.tags.append(t)
        newTag = ""
    }

    private func save() {
        Library.shared.update(wallpaper)
        dismiss()
    }
}

// MARK: - Import from URL

struct ImportURLView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from URL")
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text("Paste a direct link to a video or GIF file (e.g. from Pexels or Coverr).")
                .font(.callout).foregroundStyle(.secondary)
            TextField("https://…", text: $urlString)
                .textFieldStyle(.roundedBorder)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    importURL()
                } label: {
                    if isImporting { ProgressView().controlSize(.small) } else { Text("Import") }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty || isImporting)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func importURL() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true else {
            errorMessage = "That doesn't look like a valid URL."
            return
        }
        isImporting = true
        errorMessage = nil
        Library.shared.importFromURL(url) { wp in
            isImporting = false
            if wp != nil {
                dismiss()
            } else {
                errorMessage = "Couldn't import that file — check the link points directly to a video or GIF."
            }
        }
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
                        Picker("Shuffle from", selection: binding(\.shuffleTag)) {
                            Text("Whole library").tag(String?.none)
                            ForEach(library.allTags, id: \.self) { tag in
                                Text(tag).tag(String?.some(tag))
                            }
                        }
                    }
                }
                Section("Power") {
                    Toggle("Pause on battery", isOn: binding(\.pauseOnBattery))
                    Toggle("Pause when a fullscreen app is in front", isOn: binding(\.pauseWhenCovered))
                }
                Section("Shortcuts & tools") {
                    Toggle("Global keyboard shortcuts", isOn: binding(\.globalHotkeysEnabled))
                    if library.settings.globalHotkeysEnabled {
                        Text("⌥⇧N — Next wallpaper　⌥⇧P — Pause/Resume")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Show performance HUD", isOn: Binding(
                        get: { library.settings.showPerformanceHUD },
                        set: { newValue in
                            library.settings.showPerformanceHUD = newValue
                            PerformanceHUDController.shared.setVisible(newValue)
                        }))
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
        .frame(width: 440, height: 520)
        .onChange(of: library.settings.shuffleEnabled) { _ in
            WallpaperEngine.shared.restartShuffleTimer()
        }
        .onChange(of: library.settings.shuffleMinutes) { _ in
            WallpaperEngine.shared.restartShuffleTimer()
        }
        .onChange(of: library.settings.muted) { _ in WallpaperEngine.shared.refresh() }
        .onChange(of: library.settings.scaling) { _ in WallpaperEngine.shared.refresh() }
        .onChange(of: library.settings.mirrorDisplays) { _ in WallpaperEngine.shared.refresh() }
        .onChange(of: library.settings.globalHotkeysEnabled) { _ in HotkeyManager.shared.restart() }
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

// MARK: - Backgrounds

/// Soft, animated purple/blue gradient wash behind the whole window — replaces the flat
/// system blur with something that feels like it belongs to the same product as the icon.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()
            LinearGradient(
                colors: [Color.purple.opacity(0.25), Color.blue.opacity(0.12), Color.clear],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [Color.blue.opacity(0.18), .clear],
                center: .bottomTrailing, startRadius: 20, endRadius: 500)
        }
        .ignoresSafeArea()
    }
}

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
