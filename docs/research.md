# VoiceInk research notes (for the Windows port)

## What it is
VoiceInk is a macOS menu-bar dictation app. Press or hold a global shortcut, speak, and the transcript is pasted into whatever app has focus. Upstream: https://github.com/Beingpax/VoiceInk.

## Licence
GPL-3.0 (`LICENSE`). The Windows port in `windows/` is a derivative work in the same repo, so it is GPL-3.0 too.

## Stack
- Swift and SwiftUI, Xcode project, macOS 15+.
- Local transcription through whisper.cpp (`Infrastructure/Providers/Transcription/Whisper`), plus Parakeet via FluidAudio, GGUF models via TranscribeCpp, Apple Speech, and optional cloud providers.
- Audio capture with Core Audio AudioUnits (`Infrastructure/Audio/CoreAudioRecorder.swift`), resampled to 16 kHz mono for Whisper.
- Paste by writing `NSPasteboard` and posting a synthetic Cmd+V `CGEvent` (`Infrastructure/SystemIntegration/Paste/CursorPaster.swift`), then restoring the clipboard.
- Shortcuts via sindresorhus/KeyboardShortcuts; updates via Sparkle.

## Pipeline (`Features/Recording/Workflows/TranscriptionPipeline.swift`)
record → transcribe → `TranscriptionOutputFilter.filter` (drops `[...]`, `(...)`, `<tag>…</tag>` hallucinations and configured filler words) → trigger-word mode selection → dictionary correction → paragraph formatting → word replacements → optional AI enhancement → paste.

Filler words already exist upstream: `FillerWordManager` keeps a user-editable list (default `uh, um, uhm, umm, uhh, uhhh, hmm, hm, mmm, mm, mh, ehh`) and the filter removes each as a whole word plus a trailing `,`/`.`. It has no way to remove ambiguous fillers like "like" or "you know" without also deleting real uses ("I like it", "do you know him").

## Main features
Local models, push-to-talk or toggle shortcut, per-app "modes", screen-context-aware AI enhancement, personal dictionary and word replacements, history, audio-file import, voice assistant mode.

## macOS-only parts
Everything native: SwiftUI, AppKit menu bar and notch recorder, Core Audio, `CGEvent` paste, Accessibility API (focused element, selected text), ScreenCaptureKit OCR context, Sparkle, LaunchAtLogin, MediaRemote, XPC service, Apple Speech, Metal-accelerated whisper.cpp builds. None of it compiles on Windows, so the port is a new app that reuses the approach, not the code.

## Windows port choice
Python 3.12 (pinned with mise) + pywhispercpp (whisper.cpp bindings, same engine and GGML models as VoiceInk) + sounddevice (PortAudio) + keyboard (global hook, works without admin) + clipboard + synthetic Ctrl+V. Chosen because Python was already on this PC (no .NET SDK or Rust toolchain), every piece has Windows wheels, and the whole app stays a few hundred lines.

## Not ported
Modes, AI enhancement, screen context, history UI, dictionary, audio import, assistant, Parakeet/cloud providers, auto-update.
