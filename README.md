# Parrot

A macOS menu-bar app that reads the selected text aloud with [Kokoro](https://github.com/hexgrad/kokoro), running fully on the Mac.

- **⌥Esc** reads the selection, or stops if it's already speaking · **⌥⇧Esc** pauses or resumes · **Esc** stops (only while speaking)
- Menu: pause, skip sentence, stop, speed (0.8×–2.5×) and 28 English voices
- `parrot://speak|pause|stop|skip|faster|slower|speed?1.5|voice?af_heart` for launchers; `tinycast-commands.py` adds them to Tinycast

## Setup

Requires a Python venv with `kokoro-onnx` and `sounddevice` at `~/.local/share/local-tts/venv`, and the model files `kokoro-v1.0.int8.onnx` and `voices-v1.0.bin` in `~/.local/share/local-tts/models`.

```sh
./build.sh   # builds ~/Applications/Parrot.app and adds it to Login Items
```

Grant Accessibility access to Parrot in System Settings → Privacy & Security → Accessibility. Logs are written to `~/Library/Logs/Parrot.log`.

## Layout

- `Parrot.swift`: menu-bar app (hotkeys, selection reading, menu, URL scheme)
- `speakd.py`: local TTS daemon on `127.0.0.1:47811`, started by the app
- `icon.swift`: renders `AppIcon.png`; `build.sh` turns it into `AppIcon.icns`
