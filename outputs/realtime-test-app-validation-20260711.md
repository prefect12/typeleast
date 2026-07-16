# Typeleast Streaming Test validation — 2026-07-11

## Delivered artifact

- Branch: `codex/openai-realtime-test-app`
- Installed app: `/Applications/Typeleast Streaming Test.app`
- Bundle identifier: `com.typeleast.streaming-test`
- Version/build: `2.1.2 (21299)`
- Signing identity: `Typeleast Local Development`
- App Support: `~/Library/Application Support/TypeleastStreamingTest`
- SwiftData store: `TypeleastStreamingTest.store`

## Automated validation

- Full Swift suite: 554 executed, 3 existing snapshot tests skipped, 0 failures.
- Focused Realtime state-machine suite: 8 passed, 0 failures.
- Code signature: `codesign --verify --deep --strict` passed.
- Universal executable: arm64 + x86_64.
- SwiftPM resource bundle is present inside the installed app.
- Fallback behavior is covered by mocked handshake timeout, server error, disconnect, cancel, and final-timeout tests.
- The pretranscribed pipeline test proves a Realtime final skips batch ASR while retaining one clipboard/history side-effect path.

## Real OpenAI Realtime validation

Input was a local 6.06-second recording converted to PCM16 mono 24 kHz. The probe never prints or stores transcript text.

- Runs: 10
- Completed responses: 10/10
- Runs with delta before final commit: 10/10
- Delta events per run: 20
- Median first delta: 4,074 ms from connection start
- Median commit-to-completed: 972 ms

An additional 17.04-second probe produced 58 delta events, first delta at 4,057 ms, and completed 966 ms after commit.

## Isolation proof

- Production app remained running as PID 52212 while the test app ran separately.
- Test app process path: `/Applications/Typeleast Streaming Test.app/Contents/MacOS/Typeleast`.
- Production executable SHA-256 remained `09e2fb9f9e7d487239645a0a8287461284df51eaa1ded73c0e1be78f534a94a2`.
- Production bundle remains `com.typeleast.app`, signed by `Typeleast Local Development`.
- Production settings remain OpenAI / `zh-en` / right Command / start at login enabled.
- Test settings are OpenAI Realtime / `zh-en` / hold Right Command / start at login disabled.
- Shortcut migration V3 restores the requested hold-to-record interaction: press and hold Right Command to record, release to stop and finalize.
- The test channel never automatically opens System Settings from recording-window positioning; permissions are user-initiated from its Permissions page.
- The Realtime HUD uses stable style-specific layouts, reserves space for the TEST badge, keeps the newest transcript tail visible, and reports connecting/listening/live-caption-unavailable states without resizing on every delta.
- HUD styles keep separate visual identities in the test channel: Siri Aura uses a wider high-radius glow treatment, Apple Glass stays neutral, and Candidate Bar uses a shorter waveform layout. Short status text keeps a fixed readable column instead of wrapping mid-word.
- Production and test Keychain items both exist under different service names.
- Production and test SwiftData stores are in separate directories.

## Remaining hands-on checks

The Computer Use native UI channel failed to start, so macOS permission prompts and interactive typing into TextEdit, Chrome, and Feishu were not automated. The installed test app is running and ready for its separate Microphone and Accessibility permissions. These checks require speaking into the real microphone and observing the target apps; no permission was bypassed or altered by the validation process.
