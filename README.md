# LiveWall 🖥️✨

A lightweight, native macOS live wallpaper app. Play videos (up to 6K) and GIFs as your desktop wallpaper — behind your icons, across all your displays.

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue) ![swift](https://img.shields.io/badge/Swift-5.9-orange) ![license](https://img.shields.io/badge/license-MIT-green)

## Features

- **Native & lightweight** — pure Swift/SwiftUI + AVFoundation, hardware-accelerated video, tiny memory footprint. No Electron.
- **6K video support** — plays anything AVFoundation can decode (H.264, HEVC/H.265, ProRes…) at any resolution your Mac can handle.
- **Wide format support** — MP4, MOV, M4V, HEVC, and animated **GIF**. (MKV/WebM/AVI supported when codecs are macOS-native; otherwise convert once with HandBrake/ffmpeg.)
- **Pretty gallery** — drag-and-drop grid with live thumbnails, hover actions, and a frosted-glass look.
- **Multi-display** — mirror one wallpaper everywhere, or set a different one per screen.
- **Shuffle** — rotate wallpapers on a timer.
- **Battery saver** — auto-pauses on battery power or when a fullscreen app covers the desktop.
- **Launch at login** — set-and-forget.
- **Menu bar control** — pause/resume, next, random, gallery — all one click away.

## Install / Build

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/YOUR_USERNAME/LiveWall.git
cd LiveWall
./build.sh
open build/LiveWall.app          # or: cp -r build/LiveWall.app /Applications/
```

First launch opens the gallery. Drop in some videos or GIFs, click one, done.

> **Note:** the app is ad-hoc signed. If macOS complains on first open, right-click the app → **Open**.

## Usage

| Action | Where |
|---|---|
| Add wallpapers | Drag files into the gallery, or **Add Wallpapers** |
| Set wallpaper | Hover a card → **Set Wallpaper** |
| Per-display wallpaper | Card → `⋯` menu → **Set on display** |
| Pause / next / random | Menu bar icon (✨) |
| Shuffle, mute, scaling, battery saver, login item | Gallery → **Settings** |

## How it works

LiveWall creates a borderless window per display at the desktop window level (`kCGDesktopWindowLevel`) — the same layer macOS draws wallpaper on — so video plays *behind* your desktop icons. Videos loop seamlessly via `AVPlayerLooper`; GIFs are decoded with ImageIO and animated on a `CALayer` keyframe animation.

## License

MIT
