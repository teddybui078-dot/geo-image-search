---
name: run-geo-image-search
description: Build and launch GeoImageSearch as a real signed .app (with Photos entitlement, sandbox, and bundled globe/tokenizer resources applied) for local testing on macOS. Use whenever asked to run, launch, or test the app outside Xcode's GUI.
---

# Running GeoImageSearch locally

`swift build`/`swift run` alone produce a bare, unsigned executable with no
entitlements, no `Info.plist`, and — since `add-3dmap`/`embedding-pipeline`
merged — **it will crash** the moment `GlobeView` tries to load its bundled
resources (`Globe/Resources/*`, `Resources/tokenizer.json`), because SwiftPM's
CLI-generated resource-bundle accessor can't find them outside a real `.app`.
CLAUDE.md's own note ("swift build alone does not apply entitlements") is only
half the story — the other half, found by testing, is below.

## Why a plain `swift build` binary crashes on launch

SwiftPM generates a different `Bundle.module` accessor depending on which
build system compiles it:

- **`swift build`/`swift test`** (`.build/debug/...`): accessor checks
  `Bundle.main.bundleURL` — i.e. right next to the raw executable. Works for
  `swift run`, but that lookup path breaks for anything running inside an
  app-sandboxed process, and doesn't match a real `.app` layout at all.
- **`xcodebuild`** (compiled with `-DXcode`): accessor checks
  `Bundle.main.resourceURL` **first** — i.e. `Contents/Resources/` inside a
  real `.app`. This is the one that actually works once assembled properly.

So: build with `xcodebuild`, not `swift build`, then hand-assemble the `.app`
with the resource bundle in `Contents/Resources/` (not `Contents/MacOS/`, and
not loose at the bundle root — codesign refuses to seal loose top-level files
with "unsealed contents present in the bundle root").

## The recipe

```bash
cd <repo root>

# 1. Build via Xcode's build system (auto-detects the "GeoImageSearch" scheme
#    from Package.swift) — NOT `swift build`.
xcodebuild -scheme GeoImageSearch -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/xcode-dd build

# 2. Assemble a real .app bundle.
XDD=.build/xcode-dd/Build/Products/Debug
APP=.build/GeoImageSearch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$XDD/GeoImageSearch" "$APP/Contents/MacOS/GeoImageSearch"
cp -R "$XDD/GeoImageSearch_GeoImageSearch.bundle" "$APP/Contents/Resources/GeoImageSearch_GeoImageSearch.bundle"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string GeoImageSearch" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.geoimagesearch.app" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string GeoImageSearch" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$APP/Contents/Info.plist"

# 3. Codesign with the real entitlements (sandbox + Photos + network client).
codesign --force --deep -s - --entitlements Resources/GeoImageSearch.entitlements "$APP"
codesign --verify --deep --strict "$APP"   # should exit 0

# 4. Launch.
open "$APP"
```

`.build/` is gitignored — this never touches version control.

## Resetting state for a clean first-run test

Onboarding/UserDefaults state lives in the sandbox container, not the normal
`~/Library/Preferences/` path `defaults delete` targets:

```bash
pkill -9 -f GeoImageSearch
killall cfprefsd            # cfprefsd caches defaults in memory; a raw
                             # container delete alone won't be picked up
                             # until this is killed too
rm -rf ~/Library/Containers/com.geoimagesearch.app
```

Photos access itself is a separate, TCC-level grant (`~/Library/Application
Support/com.apple.TCC/TCC.db`) that survives container/defaults resets —
resetting it requires either `tccutil reset Photos com.geoimagesearch.app`
or revoking it manually in System Settings > Privacy & Security > Photos.

## Verifying without screen access

If screen-recording permission isn't granted for screenshot tools, drive and
read the UI via Accessibility instead — works for confirming text/controls
rendered and clicking through a flow:

```bash
osascript -e 'tell application "System Events" to tell process "GeoImageSearch" to get entire contents of front window'
osascript -e 'tell application "System Events" to tell process "GeoImageSearch" to click button 1 of group 1 of window "GeoImageSearch"'
```

Kill stray old processes first (`pgrep -fl GeoImageSearch`) — if more than
one process shares the exact name "GeoImageSearch", System Events' `tell
process "GeoImageSearch"` is ambiguous and may query the wrong one.
