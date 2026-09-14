# kiclient

A featherweight, battery-friendly macOS client for Kick.com streams and chat. Built with Swift & libmpv so your Mac stays cool and quiet. (still work in progress about being cool :/ )

---

### Why kiclient?

Watching Kick in a bloated browser tab easily eats 1–2 GB of RAM, spins up your laptop fans, and drains your battery.

**kiclient** is built natively for macOS:

- Streams video with hardware-accelerated **libmpv** + **Apple VideoToolbox**.
- Sits comfortably around **~100 MB of RAM** and barely touches your CPU.
- Looks and feels like a real Mac app, not a wrapped web page.

---

## Highlights

- 📺 **Buttery Smooth Video**: Full hardware decode with zero frame drops and locked audio/video sync.
- 💬 **Instant Live Chat**: Reads chat directly via WebSocket with zero login needed. Fast, smooth, and capped so it never bogs down.
- 🔐 **Send Messages Safely**: Log in with your Kick account via OAuth 2.1 (PKCE). Your tokens are encrypted directly inside your macOS Keychain.
- 🍃 **Smart Eco Mode**: When you hide or minimize the window, video rendering stops (0% GPU) while your audio and chat keep playing in the background.
- 🎛 **Quality & Sizing Controls**: Pick between Auto, 1080p60, 720p, etc., and scale the chat text size to your liking.
- 🛠 **Dev Console (`⌘D`)**: Live RAM & CPU monitors, log stream, and an interactive mpv prompt for anyone who likes to tinker.

---

## Shortcuts

| Key | Action |
| --- | --- |
| `Space` | Play / Pause |
| `⌘D` | Toggle Dev Console |
| `⌘,` | Settings |
| `⌘⌥C` | Toggle Chat Panel |

---

## Getting Started

### Prerequisites

You'll need `mpv` and `xcodegen` installed via [Homebrew](https://brew.sh):

```bash
brew install mpv xcodegen
```

### Build & Run

```bash
git clone <repo-url>
cd kiclient
xcodegen generate
open kiclient.xcodeproj
```

Hit `⌘R` in Xcode to run, or run the test suite from your terminal:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project kiclient.xcodeproj -scheme kiclient -destination 'platform=macOS,arch=arm64'
```

---

## Good to Know

- **Zero Electron / WebView**: Strictly native AppKit & SwiftUI.
- **Privacy First**: No telemetry, no trackers, and zero credentials in plaintext files. Everything private stays inside your macOS Keychain.

---

## Docs & Architecture

If you want to dive deeper into the code:

- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — System design & modules
- [`UI_GUIDELINES.md`](./UI_GUIDELINES.md) — Design system & HIG guidelines
- [`PERFORMANCE.md`](./PERFORMANCE.md) — Benchmarks & memory targets
- [`KICK_API_NOTES.md`](./KICK_API_NOTES.md) — Reverse-engineered Kick endpoints
- [`CHANGELOG.md`](./CHANGELOG.md) — What changed recently

---

## License

To be determined by the project owner.
