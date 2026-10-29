"""VoiceInk for Windows: hold the hotkey, speak, release, and the cleaned transcript is pasted."""

import argparse
import os
import re
import shutil
import threading
import time
import wave
from pathlib import Path

import keyboard
import numpy as np
import pyperclip
import sounddevice as sd
from pywhispercpp.model import Model

from .filler import DEFAULT_WORDS_FILE, load_words, remove_fillers

RATE = 16000
MIN_SECONDS = 0.3
WORDS_FILE = Path(os.environ["APPDATA"]) / "VoiceInk" / "filler_words.txt"
# Same bracketed-hallucination patterns as upstream TranscriptionOutputFilter, e.g. "[BLANK_AUDIO]".
HALLUCINATIONS = re.compile(r"\[.*?\]|\(.*?\)|\{.*?\}")


def clean(text: str) -> str:
    return remove_fillers(HALLUCINATIONS.sub("", text), load_words(WORDS_FILE))


class MicRecorder:
    def start(self):
        self.chunks = []
        self.stream = sd.InputStream(
            samplerate=RATE, channels=1, dtype="float32",
            callback=lambda data, *_: self.chunks.append(data.copy()),
        )
        self.stream.start()

    def stop(self) -> np.ndarray:
        self.stream.stop()
        self.stream.close()
        return np.concatenate(self.chunks)[:, 0] if self.chunks else np.zeros(0, np.float32)


class WavRecorder:
    """Stands in for the mic with a 16 kHz mono 16-bit WAV, for unattended end-to-end runs."""

    def __init__(self, path: Path):
        with wave.open(str(path)) as f:
            assert (f.getframerate(), f.getnchannels(), f.getsampwidth()) == (RATE, 1, 2), "need 16 kHz mono 16-bit"
            self.samples = np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(np.float32) / 32768

    def start(self):
        pass

    def stop(self) -> np.ndarray:
        return self.samples


def paste(text: str):
    # shortcut: restores only text clipboard content; images or files copied before dictation are lost.
    previous = pyperclip.paste()
    pyperclip.copy(text)
    keyboard.send("ctrl+v")
    time.sleep(0.3)  # let the target app read the clipboard before restoring it
    pyperclip.copy(previous)


class PushToTalk:
    """Records while `key` is held. Pressing any other key meanwhile means the key was a modifier, so the take is dropped."""

    def __init__(self, key: str, recorder, on_audio):
        self.key, self.recorder, self.on_audio = key, recorder, on_audio
        self.held = False
        keyboard.hook(self._on_event)

    def _on_event(self, event):
        if event.name != self.key:
            if self.held and event.event_type == keyboard.KEY_DOWN:
                self.interrupted = True
            return
        if event.event_type == keyboard.KEY_DOWN and not self.held:
            self.held, self.interrupted, self.started = True, False, time.monotonic()
            self.recorder.start()
            print("recording...", flush=True)
        elif event.event_type == keyboard.KEY_UP and self.held:
            self.held = False
            audio = self.recorder.stop()
            if self.interrupted or time.monotonic() - self.started < MIN_SECONDS:
                print("dropped (too short, or used as a modifier)", flush=True)
                return
            threading.Thread(target=self.on_audio, args=(audio,)).start()


def mic_check(seconds: float = 2.0):
    print(f"mic: {sd.query_devices(kind='input')['name']}", flush=True)
    audio = sd.rec(int(seconds * RATE), samplerate=RATE, channels=1, dtype="float32", blocking=True)[:, 0]
    print(f"recorded {len(audio) / RATE:.1f}s, peak {np.abs(audio).max():.4f}, rms {np.sqrt(np.mean(audio**2)):.4f}")


def main():
    parser = argparse.ArgumentParser(prog="voiceink", description=__doc__)
    parser.add_argument("--hotkey", default="right ctrl", help="key to hold while speaking (default: right ctrl)")
    parser.add_argument("--model", default="base.en", help="whisper.cpp model name, downloaded on first use")
    parser.add_argument("--fake-mic", type=Path, metavar="WAV", help="use this WAV instead of the microphone")
    parser.add_argument("--once", action="store_true", help="exit after the first paste")
    parser.add_argument("--clean", metavar="TEXT", help="print TEXT with filler words removed, then exit")
    parser.add_argument("--mic-check", action="store_true", help="record 2 s from the default mic and report levels")
    args = parser.parse_args()

    if not WORDS_FILE.exists():
        WORDS_FILE.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(DEFAULT_WORDS_FILE, WORDS_FILE)
    if args.clean is not None:
        return print(clean(args.clean))
    if args.mic_check:
        return mic_check()

    print(f"loading {args.model}...", flush=True)
    model = Model(args.model, redirect_whispercpp_logs_to=None)
    done = threading.Event()

    def on_audio(audio: np.ndarray):
        heard = " ".join(s.text.strip() for s in model.transcribe(audio)).strip()
        text = clean(heard)
        print(f"heard:  {heard}\npasted: {text}", flush=True)
        if text:
            paste(text)
        if args.once:
            done.set()

    PushToTalk(args.hotkey, WavRecorder(args.fake_mic) if args.fake_mic else MicRecorder(), on_audio)
    print(f"ready. hold [{args.hotkey}] to dictate. filler words: {WORDS_FILE}", flush=True)
    done.wait()


if __name__ == "__main__":
    main()
