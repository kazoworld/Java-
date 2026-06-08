# Ultrafin

An ultra-modern, buttery-smooth **Jellyfin** client for **iOS** and **tvOS**.

Ultrafin pairs a clean SwiftUI interface with a **hybrid playback core** —
Apple's `AVPlayer` for the smoothest, hardware-accelerated 60fps path, with a
**VLCKit** fallback (the same media engine Swiftfin relies on) for the long tail
of codecs and containers that AVFoundation won't decode. Everything is
customizable from a live Settings screen: accent color, theme, motion, and the
playback engine policy.

> Jellyfin and the Swiftfin media core are open source. Ultrafin is an
> independent client built on the Jellyfin REST API.

---

## Highlights

- **Hybrid player** — AVPlayer by default, automatic VLCKit fallback for
  unsupported formats. Selectable policy: Hybrid / Native only / VLCKit only.
- **60fps interface** — `@Observable` stores, lazy stacks, throttled time
  observers, GPU-composited video layer, and an overlay that's the only thing
  animating during playback.
- **Modern design system** — frosted glass surfaces, rounded type scale,
  shimmer placeholders, parallax hero artwork, five accent themes.
- **Core flows** — server discovery → sign in → Home (Continue Watching /
  Recently Added / Libraries) → library browse → item detail → playback with
  resume + progress reporting.
- **iOS + tvOS** from one shared codebase.

## Architecture

```
Ultrafin/Sources/
├── App/                 App entry, root routing, AppState (auth/session phases)
├── Core/
│   ├── Models/          ServerConnection, UserSession, MediaItem, playback models
│   ├── Networking/      JellyfinClient (async REST actor), responses, errors
│   └── Services/        Server discovery, Keychain session store, settings, device id
├── DesignSystem/        Colors, typography, spacing, reusable components
└── Features/
    ├── Onboarding/      Server connect
    ├── Auth/            Login
    ├── Home/            Dashboard rails
    ├── Library/         Libraries grid + contents
    ├── ItemDetail/      Parallax detail + play
    ├── Player/          Hybrid engine (protocol + AVPlayer + VLCKit) & controls
    ├── Settings/        Customizable options
    ├── Main/            Tab shell
    └── Shared/          MediaRail / MediaCard
```

**Playback engine design.** The UI talks only to the `PlaybackEngine` protocol.
`VideoPlayerViewModel` resolves the stream via `/Items/{id}/PlaybackInfo`, then
the hybrid policy picks `AVPlaybackEngine` (direct-play/HLS) or
`VLCPlaybackEngine` (everything else). Swapping or adding engines never touches
the views.

**Networking.** `JellyfinClient` is a self-contained `actor` implementing the
Jellyfin REST endpoints the app uses (auth, views, resume, latest, items,
images, playback info, progress). The official `jellyfin-sdk-swift` is wired
into the project so screens can migrate onto the generated client incrementally.

## Requirements

- macOS with **Xcode 15+**
- iOS 17 / tvOS 17 deployment target
- [XcodeGen](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`)

## Getting started

```bash
# 1. Generate the Xcode project from project.yml
xcodegen generate

# 2. Open it
open Ultrafin.xcodeproj

# 3. Set your Apple Developer Team in project.yml (DEVELOPMENT_TEAM) or in Xcode,
#    then select the Ultrafin-iOS or Ultrafin-tvOS scheme and run.
```

Swift Package dependencies (`jellyfin-sdk-swift`, `VLCKit`) resolve on first
build. If you build **without** VLCKit, the app still compiles and runs on the
native AVPlayer path — the hybrid coordinator detects VLCKit's absence and stays
on AVPlayer.

### On first launch

1. Enter your Jellyfin server address (e.g. `media.example.com` or
   `192.168.1.10:8096` — scheme/port optional, Ultrafin probes for you).
2. Sign in with your Jellyfin username/password.
3. Browse and play. Sessions persist (token in Keychain) for auto sign-in.

## Customization

Settings → live, app-wide:

| Group | Options |
|-------|---------|
| Appearance | Theme (system/dark/light), rich motion & parallax, 5 accent colors |
| Playback | Engine policy (Hybrid/Native/VLCKit), auto-resume, skip interval, max buffer |
| Account | Signed-in user, server info, sign out |

## Notes & next steps

- **App icons** are placeholders (empty image slots). Drop artwork into
  `Ultrafin/Resources/Assets.xcassets` before shipping.
- **tvOS controls** currently use the touch/drag scrubber; focus-engine
  remote navigation for the transport is a natural follow-up.
- Episode/season hierarchy, search, subtitle/audio track selection, and
  Chromecast are scoped for future iterations.

## License

The Jellyfin server, SDK, and the VLCKit/Swiftfin media stack are licensed by
their respective projects. Add your own license for the Ultrafin app code.
