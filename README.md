# Typeleast

Typeleast is a macOS menu bar app for fast dictation, cleanup, and paste-back into the app you were using. It records a short voice note, transcribes it with a local or cloud engine, optionally applies semantic correction, and copies or pastes the result.

<p align="center">
  <img src="https://github.com/prefect12/typeleast/blob/main/TypeleastIcon.png" width="128" height="128" alt="Typeleast icon">
</p>

## Features

- Global hotkey, Express Mode, and optional press-and-hold recording.
- Cloud transcription with OpenAI or Google Gemini.
- Local transcription with WhisperKit or Parakeet-MLX.
- Optional semantic correction through local MLX models or the active cloud provider.
- Transcription history, search, retention controls, and usage insights.
- Smart Paste for automatically inserting transcribed text into the previous app.
- Provider, model, permission, hotkey, and history controls in the Typeleast dashboard.
- Local-first defaults: no analytics, API keys in Keychain, and local engines keep audio on device.

## Requirements

- macOS 14.0 or later.
- Apple Silicon recommended for local MLX and Parakeet workflows.
- Xcode 15 or Swift 5.9+ when building from source.
- Optional API keys for OpenAI or Google Gemini cloud providers.
- Disk space for local models: WhisperKit and Parakeet models can require several GB depending on selected model.

## Installation

### Homebrew

```bash
brew tap prefect12/tap
brew install typeleast
open -a Typeleast
```

To update:

```bash
brew update
brew upgrade typeleast
```

### GitHub Release

Download `Typeleast.zip` from [Releases](https://github.com/prefect12/typeleast/releases), unzip it, and move `Typeleast.app` to `/Applications`.

### Build From Source

```bash
git clone https://github.com/prefect12/typeleast.git
cd typeleast
make build
open Typeleast.app
```

## Setup

1. Launch Typeleast.
2. Open Settings from the menu bar.
3. Choose a transcription provider:
   - OpenAI or Gemini: enter an API key and optional custom endpoint.
   - WhisperKit: pick and download a local CoreML model.
   - Parakeet-MLX: install dependencies, select a model, and verify the download.
4. Configure semantic correction if needed.
5. Optional: enable history, Smart Paste, Express Mode, press-and-hold recording, start at login, and completion sound.

Smart Paste and press-and-hold recording require macOS privacy permissions. Typeleast opens the relevant Settings panes when a permission is missing.

## Usage

- Press the configured hotkey, default `Cmd+Shift+Space`, to open recording.
- Press Space to start or stop recording in the recording window.
- Use Express Mode to start and stop recording directly from the hotkey.
- Use press-and-hold mode to record while holding the configured modifier key.
- Use "Transcribe Audio File..." from the menu bar to transcribe an existing file.

After transcription, Typeleast copies the result to the clipboard. If Smart Paste is enabled, it sends paste to the previously focused app.

## Data And Privacy

- API keys are stored in macOS Keychain under the Typeleast service.
- Local WhisperKit, Parakeet-MLX, and local MLX correction run on device.
- OpenAI and Gemini providers send audio or text to the configured cloud endpoint.
- History is local and controlled by the retention setting.
- Typeleast does not collect analytics.

## Development

Use SwiftPM for day-to-day development:

```bash
swift build
swift test
swift run
```

Use the release script only when creating a distributable app bundle:

```bash
make build
```

Notarized builds require a Developer ID signing identity and:

```bash
export TYPELEAST_APPLE_ID="you@example.com"
export TYPELEAST_APPLE_PASSWORD="app-specific-password"
export TYPELEAST_TEAM_ID="TEAMID"
make build-notarize
```

## Release

1. Update `VERSION`.
2. Run `make build` or `make build-notarize`.
3. Create a GitHub release with `Typeleast.zip`.
4. Run `make update-brew-cask` or `make publish-brew-cask` when publishing through the Homebrew tap.

## Dependencies

- [Alamofire](https://github.com/Alamofire/Alamofire)
- [HotKey](https://github.com/soffes/HotKey)
- [WhisperKit](https://github.com/argmaxinc/WhisperKit)
- [MLX](https://github.com/ml-explore/mlx)
- [parakeet-mlx](https://github.com/senstella/parakeet-mlx)

## License

Typeleast is released under the MIT License. See [LICENSE](LICENSE).
