# LunaAnime 🍥

A SwiftUI iOS app for streaming and downloading anime, inspired by the UI of [cranci1/Luna](https://github.com/cranci1/Luna). Instead of services, LunaAnime uses pluggable **anime provider scrapers** (AnimePahe, Gogoanime, Hianime) — modeled on the architecture of [StrawVerse](https://github.com/TheYogMehta/StrawVerse), [Senpwai](https://github.com/SenZmaKi/Senpwai), and [animdl](https://github.com/justfoolingaround/animdl).

> ⚠️ **Legal Notice**: This project is for educational and research purposes only. The developers do not host, store, or distribute any copyrighted media. All streams are sourced from third-party sites via user-driven scraping. You are responsible for compliance with your local laws.

---

## ✨ Features

- 🏠 **Home** — trending rows, recently added, search
- ▶️ **Continue Watching** — pick up exactly where you left off
- 📚 **Library** — every anime you've downloaded, with offline playback
- 🔍 **Search** — across the active anime provider
- 🎙️ **Dub / Sub** — choose per-episode or set a default in Settings
- ⬇️ **Downloads** — single episodes or full-season batch downloads
- 📤 **Export** — share downloaded files to the Files app, AirDrop, VLC, etc.
- ⚙️ **Providers Setting** — pick which scraper (AnimePahe / Gogoanime / Hianime) the app uses
- 🌙 **Modern SwiftUI UI** — dark theme, posters, gradient hero headers

---

## 🛠️ Setup (Xcode)

This repo contains the **source tree only**. To turn it into a buildable app:

1. Open Xcode (15+ recommended; iOS 17 deployment target).
2. **File → New → Project → iOS → App**
   - Product Name: `LunaAnime`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None** (we add Core Data manually below)
3. Delete the auto-generated `ContentView.swift` and the auto-generated `*App.swift` (we have our own).
4. Drag the entire `LunaAnime/` folder from this repo into the new Xcode project (choose **"Create groups"** and **"Copy items if needed"**). Make sure "Add to target: LunaAnime" is checked.
5. Add **Core Data**:
   - File → New → File → Data Model
   - Name it `LunaAnime.xcdatamodeld`
   - Recreate the schema described in [`LunaAnime/Persistence/SCHEMA.md`](LunaAnime/Persistence/SCHEMA.md) (or just use the file shipped in `Persistence/`).
6. Add the **AVKit**, **CoreData**, **UniformTypeIdentifiers** frameworks if Xcode didn't add them automatically (Settings → General → Frameworks, Libraries…).
7. In **Signing & Capabilities** add the **Background Modes** capability and check **"Background fetch"** + **"Background processing"** (so downloads keep going in the background).
8. Replace the auto-generated `Info.plist` with the one in `LunaAnime/App/Info.plist` (or merge keys — the critical ones are `NSAppTransportSecurity` exceptions, file-sharing support, and background-mode entries).

### Build & Run
Pick an iPhone simulator (iOS 17+) → ⌘R.

---

## 🏗️ Project Layout

```
LunaAnime/
├── App/                  SwiftUI app entry + global environment
├── Models/               Value-type domain models
├── Persistence/          Core Data stack and entities
├── Scrapers/             Pluggable anime providers (protocol + 3 impls)
├── Networking/           HTTP client, HTML/JSON parsers
├── Downloads/            URLSession background download manager
├── Player/               AVKit-based player with progress persistence
├── Preferences/          UserDefaults wrapper for settings
├── ViewModels/           ObservableObject VMs (MVVM)
├── Views/                All SwiftUI screens
│   ├── Home/             Home tab
│   ├── Search/           Search tab
│   ├── Continue/         Continue Watching tab
│   ├── Library/          Library (downloaded) tab
│   ├── Anime/            Anime detail / season / episode list
│   ├── Player/           Fullscreen player
│   ├── Settings/         Settings + Providers picker
│   └── Components/       Reusable cards, rows, top bar
└── Utilities/            Theme, logger, extensions
```

---

## 🔌 Provider System

LunaAnime uses a **protocol-oriented** provider abstraction (Swift's `protocol` + `async/await`):

```swift
public protocol AnimeProvider: Identifiable, Sendable {
    var id: String { get }
    var displayName: String { get }
    var iconSystemName: String { get }
    var capabilities: ProviderCapabilities { get }

    func search(query: String) async throws -> [AnimeSummary]
    func fetchAnimeDetails(id: String) async throws -> AnimeDetails
    func fetchEpisodes(animeId: String, translation: Translation) async throws -> [Episode]
    func resolveStream(episodeId: String, translation: Translation) async throws -> [StreamSource]
}
```

`ProviderRegistry` ships with three concrete providers out of the box:

| Provider ID    | Source site  | Sub | Dub |
|----------------|--------------|:---:|:---:|
| `animepahe`    | animepahe.com|  ✅ |  ✅ |
| `gogoanime`    | gogoanime.*  |  ✅ |  ✅ |
| `hianime`      | hianime.to   |  ✅ |  ✅ |

Users can switch providers in **Settings → Providers**. All features (search, browse, stream, download) automatically route through the active provider.

Because these third-party sites change their HTML/layout frequently, the scraper logic is intentionally **isolated and easy to patch** — if a site breaks, only one file needs updating.

---

## 🎬 Player & Downloads

- The video player uses `AVPlayer` from `AVKit` and supports both **HLS (.m3u8)** and direct **MP4** sources.
- Downloads are powered by `URLSession` with a **background configuration**, so they continue when the app is backgrounded.
- Each episode's progress is stored in Core Data, so the **Continue** tab picks up exactly where you left off.
- Library files are stored under `Documents/Downloads/<Anime>/<Episode>.mp4` and can be exported via a system share sheet (AirDrop, Files, VLC, etc.).

---

## 🧪 Tested With

- Xcode 15.4
- iOS 17.5 Simulator
- iPhone 14 / 15 device builds

---

## 📜 Credits

UI inspiration: [cranci1/Luna](https://github.com/cranci1/Luna)  
Scraping patterns: [TheYogMehta/StrawVerse](https://github.com/TheYogMehta/StrawVerse), [SenZmaKi/Senpwai](https://github.com/SenZmaKi/Senpwai), [justfoolingaround/animdl](https://github.com/justfoolingaround/animdl)
