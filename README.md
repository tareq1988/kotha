# Kotha (কথা)

A minimal, personal macOS voice-typing app — a trimmed-down Spokenly.

- **Hold Right ⌘** → English, transcribed **locally** with NVIDIA Parakeet (FluidAudio / CoreML, offline).
- **Hold Right ⌥** → Bangla, transcribed **online** with Soniox.

Release the key → it transcribes → it pastes the text into whatever app is focused.

## Build & run

```bash
chmod +x run.sh
./run.sh
```

This generates the Xcode project (via XcodeGen), builds, and launches the menu-bar app.
Or open `Kotha.xcodeproj` in Xcode and press Run.

## First-time setup

1. **Microphone** — macOS prompts on first dictation. Allow it.
2. **Accessibility** — on first launch Kotha asks for Accessibility permission
   (needed for the global hotkeys and to paste). Grant it in
   *System Settings → Privacy & Security → Accessibility*, then relaunch.
3. **Soniox key (for Bangla)** — open the menu-bar icon → *Settings…*, paste your
   Soniox API key (stored in the Keychain), and click Save.

> Re-granting Accessibility after each rebuild is expected because the app is
> ad-hoc signed. For day-to-day use, build once and keep that copy.

## How it works

| Piece | File |
|-------|------|
| Global right-⌘ / right-⌥ hold detection (CGEventTap) | `Sources/HotkeyMonitor.swift` |
| Mic capture → 16 kHz mono Float | `Sources/AudioRecorder.swift` |
| English (local Parakeet) | `Sources/ParakeetTranscriber.swift` |
| Bangla (Soniox async REST) | `Sources/SonioxTranscriber.swift` |
| Paste into focused app | `Sources/TextInserter.swift` |
| Orchestration / state | `Sources/AppState.swift` |
| Menu bar + Settings + listening pill | `Sources/MenuView.swift`, `SettingsView.swift`, `ListeningPanel.swift` |

## Notes / tunables

- English model: `AsrModels.downloadAndLoad(version: .v3)` in `ParakeetTranscriber.swift`.
  Switch to `.v2` for English-only with higher recall.
- Soniox model: `stt-async-v5` with `language_hints: ["bn", "en"]` in `SonioxTranscriber.swift`.
- Hotkeys are the right-side modifier key codes (54 = right ⌘, 61 = right ⌥) in `HotkeyMonitor.swift`.
- Bangla path is **batch**: it uploads the recorded clip on release and waits for the result,
  so longer clips take a moment. (Soniox also has a realtime WebSocket API if you want lower latency later.)
