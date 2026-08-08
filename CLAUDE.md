# Ultrafin — working notes

## Always end a reply with the pull-and-build commands

The Xcode project is **generated, not committed** (`Ultrafin.xcodeproj/` is in
`.gitignore`; `project.yml` is the source of truth). Sources are picked up by
directory, so any commit that adds, renames or deletes a file leaves a stale
project on disk that still compiles the old file list — usually surfacing as
"cannot find X in scope" for something that plainly exists.

So **every reply that pushes a commit ends with the block below**, verbatim, even
when only existing files changed. It costs the user nothing to run twice and
costs them a confusing build failure to skip once.

```bash
git pull
xcodegen generate
```

## Branch and CI

- All work goes on `claude/jellyfin-ios-tvos-app-3NnRr` (draft PR #1).
- CI builds **both** iOS and tvOS on macos-26. tvOS is the one that catches
  API-availability slips (`listRowSeparator`, `editMode`, `matchedTransitionSource`
  and friends are iOS-only), so a green iOS build alone proves nothing.
- Wait for CI after pushing and report the real result.

## Build marker

`BuildInfo.marker` is read in Music → Settings. Bump it whenever a change needs
confirming on hardware — Xcode will happily relaunch the previously-installed app
after a failed build, and the marker is the only way to answer "am I actually on
the new code?" from the screen.

## Platform split

The user works one side at a time and says which: **Media** (movies/TV) or
**Music**. Don't carry a change across to the other side unless asked — the
Apple-Music red belongs to Music, and Media keeps its own accent palette
(`SettingsStore.accent` resolves this per `AppModeState`).
