# Contributing To Typeleast

Typeleast is a maintainer-led macOS app. Contributions are welcome when they preserve the app's focus: fast dictation, reliable transcription, useful correction, and low-friction paste-back.

## Development Setup

Requirements:

- macOS 14.0 or later
- Xcode 15 or Swift 5.9+
- Git

Clone and validate:

```bash
git clone https://github.com/prefect12/typeleast.git
cd typeleast
swift build
swift test
```

## Daily Workflow

Use SwiftPM for normal development:

```bash
swift build
swift test
swift run
```

Use `make build` only when you need a distributable `.app` bundle. Release builds sign the app and may affect macOS privacy permissions when installed over an existing app.

## Code Guidelines

- Keep product changes scoped and visible in the macOS app.
- Preserve `com.typeleast.app` unless a release plan explicitly changes app identity.
- Keep API keys in Keychain and local data under Typeleast's Application Support directory.
- Prefer existing SwiftUI/AppKit patterns in `Sources/Views`, `Sources/Managers`, and `Sources/Services`.
- Add or update tests for behavior changes.

## Validation

Before opening a pull request:

```bash
swift build
swift test
```

For release-affecting changes:

```bash
make build
codesign --verify --verbose Typeleast.app
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Typeleast.app/Contents/Info.plist
```

The bundle identifier should remain `com.typeleast.app`.

## Release Notes

Update `VERSION` for releases. The Homebrew cask flow is documented in [HOMEBREW.md](HOMEBREW.md).
