# Ultrafin

[![CI](https://github.com/kazoworld/Java-/actions/workflows/ci.yml/badge.svg)](https://github.com/kazoworld/Java-/actions/workflows/ci.yml)

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
- **tvOS focus-engine native** — focusable poster cards that lift/scale/glow
  under the Siri Remote, and a player driven entirely by the remote (Play/Pause
  toggles, Menu exits, swipe ◀ ▶ scrubs, click toggles). The thing Swiftfin
  does well and touch-port clients get wrong — plus the customization Swiftfin
  lacks.
- **iOS + tvOS** from one shared codebase with per-platform interaction models.

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

The project builds with **no external dependencies** by default, so a clean
checkout compiles immediately. The VLCKit fallback engine is an opt-in (see
below); without it the hybrid player runs on the native AVPlayer path — the
coordinator detects VLCKit's absence and stays on AVPlayer.

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

## Continuous integration

`.github/workflows/ci.yml` builds **both** the iOS and tvOS targets on every
push and PR (simulator builds, no signing/secrets). It generates the project
with XcodeGen and runs `xcodebuild` per platform, so compile breakage is caught
automatically — including on the open PR.

## Shipping to TestFlight

Release automation lives in `fastlane/` and `.github/workflows/testflight.yml`
(a manual **workflow_dispatch** — choose iOS, tvOS, or both). Both apps ship
under one App Store Connect record (shared bundle id `com.ultrafin.app`).

It uses an **App Store Connect API key** for auth (no Apple ID/2FA in CI) and
[`match`](https://docs.fastlane.tools/actions/match/) for code signing. Add
these as repository secrets to arm it:

| Secret | Purpose |
|--------|---------|
| `APP_STORE_CONNECT_KEY_ID` / `APP_STORE_CONNECT_ISSUER_ID` / `APP_STORE_CONNECT_KEY_CONTENT` | App Store Connect API key (`.p8` base64-encoded) |
| `MATCH_GIT_URL` / `MATCH_PASSWORD` / `MATCH_GIT_BASIC_AUTHORIZATION` | `match` certificate repo + access |
| `DEVELOPMENT_TEAM` / `APP_STORE_CONNECT_TEAM_ID` / `FASTLANE_APPLE_ID` | Team + account identifiers |

One-time setup on a Mac:

```bash
bundle install
bundle exec fastlane match appstore        # create signing assets
# Create the app record (iOS + tvOS) in App Store Connect, then:
bundle exec fastlane ios beta              # or: tvos beta
```

## Enabling the VLCKit fallback

The hybrid player's VLCKit path is gated behind `#if canImport(VLCKit)`, so it
activates automatically once the package is linked — no code changes:

1. In `project.yml`, uncomment the `packages:` block and the per-target
   `dependencies:` entries (confirm the VLCKit package URL/version for your
   Xcode toolchain first).
2. `xcodegen generate` and rebuild.

Settings → Playback then offers the full Hybrid / Native / VLCKit policy.

## Notes & next steps

- **App icons** are placeholders (empty image slots). Drop artwork into
  `Ultrafin/Resources/Assets.xcassets` before shipping.
- **tvOS** uses the focus engine for browsing and the Siri Remote for playback
  (Play/Pause, Menu, swipe-to-scrub, click). Continuous hold-to-scrub with a
  thumbnail preview is a nice future enhancement.
- Episode/season hierarchy, search, subtitle/audio track selection, and
  Chromecast are scoped for future iterations.

## License

The Jellyfin server, SDK, and the VLCKit/Swiftfin media stack are licensed by
their respective projects. Add your own license for the Ultrafin app code.
