# VoiceInk for Windows

A small Windows port of [VoiceInk](https://github.com/Beingpax/VoiceInk). Hold Right Ctrl, speak, release, and the transcript is pasted into the focused app. Transcription runs locally with whisper.cpp. Filler words are stripped before the paste.

It reuses VoiceInk's approach, not its Swift code. See [docs/research.md](../docs/research.md) for what was and wasn't ported. GPL-3.0, like upstream.

## Install

Needs [mise](https://mise.jdx.dev). From this folder:

```powershell
mise install
mise exec -- python -m venv .venv
.venv\Scripts\python -m pip install -e ".[test]"
```

## Run

```powershell
.venv\Scripts\voiceink.exe
```

The first run downloads the `base.en` model (about 140 MB). When it prints `ready`, hold Right Ctrl in any app and talk. A tap shorter than 0.3 s, or Right Ctrl used with another key (Ctrl+C), is ignored.

Options: `--hotkey "f9"` picks another key, `--model small.en` a bigger model, `--mic-check` reports mic levels, `--clean "text"` shows what the filter does to a sentence.

## Filler words

The list lives at `%APPDATA%\VoiceInk\filler_words.txt`, copied from [filler_words.txt](voiceink_win/filler_words.txt) on first run. Edit it any time. It is re-read on every dictation.

- `um` is removed wherever it appears as a whole word.
- `~like` is removed only when set off by commas or at a sentence edge. "We should, like, ship it" loses it, "I like it" keeps it.

Only the text is cleaned. The audio is never cut.

## Test

```powershell
.venv\Scripts\python -m pytest -q
powershell -ExecutionPolicy Bypass -File scripts\e2e.ps1
```

`e2e.ps1` speaks a sentence with Windows TTS, feeds it to the app in place of the mic, holds Right Ctrl, and checks that the cleaned text landed in a new Notepad tab.
