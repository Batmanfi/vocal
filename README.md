# Vocal

Vocal is a macOS push-to-talk dictation app. Hold Right Option (or a shortcut of your choice) to record, release to transcribe locally with NVIDIA Parakeet via MLX, then paste the text into the focused app. It runs as a normal Dock app with a window (Home + History) and also keeps a menu-bar item for quick status and actions.

The macOS shell is native Swift/AppKit. The transcription model runs in a long-lived Python daemon because the pinned engine, `parakeet-mlx`, is a Python package.

Everything runs locally — audio never leaves your machine.

## Requirements

- **Apple Silicon Mac (M1 or newer).** Transcription runs on MLX, which is Apple-Silicon only — Intel Macs are not supported.
- **macOS 13 (Ventura) or newer.**
- **Xcode command-line tools** (for `swift build`): `xcode-select --install`.
- **Python 3.11** and **ffmpeg** — see [Python ASR Environment](#python-asr-environment).

## Quick start

```bash
git clone https://github.com/Batmanfi/vocal.git
cd vocal

# one-time Python setup (see "Python ASR Environment" for details)
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
brew install ffmpeg

# build and launch
./script/build_and_run.sh
```

The script builds the SwiftPM executable, stages `dist/Vocal.app`, and launches the app bundle.

> **Gatekeeper:** the app is signed ad-hoc (or with a self-signed identity), not notarized by
> Apple. Because you build it yourself from source the first launch should open normally, but if
> macOS blocks it, right-click `Vocal.app` → **Open**, or allow it under
> System Settings → Privacy & Security.

## Install (open from Spotlight / Launchpad)

To use Vocal like a normal app — launchable from Spotlight (⌘Space) or Launchpad instead of
re-running the build script — install it into `/Applications`:

```bash
./script/install.sh
```

This builds the bundle, pins the Python venv path in `config.json` (so the installed copy
finds `parakeet-mlx` even though `.venv` lives next to the project), copies the app to
`/Applications/Vocal.app` with the same signing identity, and launches it. Because the
signing identity is unchanged, your granted permissions carry over.

Once running it stays in the menu bar, so day-to-day you rarely need to reopen it. To have
it start automatically at login, use the **Launch at Login** item in the menu-bar menu.

## Features (menu bar)

- **History…** — a searchable window of past transcriptions (stored in
  `~/.config/vocal/history.json`). Double-click an entry, or select it and click **Copy**,
  to put it back on the clipboard.
- **Change Shortcut…** — opens a recorder. Press any key combo (e.g. ⌥Space) or a single
  modifier alone (e.g. Right ⌥) to set the push-to-talk trigger. Saved to `config.json`.
- **Launch at Login** — toggles Vocal as a login item.

### Two ways to record

- **Hold to talk** (default Right ⌥): hold the key, speak, release to insert.
- **Toggle / continuous** (default ⌥Space): press once to start (a live waveform
  recording window appears), press again to stop and insert. Both shortcuts are
  configurable in Settings.

### Recording window

A floating waveform appears while recording. Choose **Classic**, **Mini**, or **None** in
Settings (`recording_window` in config).

### Spoken numbers → digits

When enabled (Settings → "Convert spoken numbers to digits"), spoken numbers become digits
in the inserted text: "twenty" → "20", "twenty-five" → "25", "one hundred twenty three" →
"123". Sequences of single digits concatenate (phone numbers): "five five five one two
three four" → "5551234". Toggle with `format_numbers` in config.

## Python ASR Environment

Create the local Python environment once, from the repo root:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
brew install ffmpeg
```

On first launch with dependencies installed, the model downloads into the Hugging Face cache. Later launches can run offline.

The app sets `HF_HUB_DISABLE_XET=1` for the Parakeet helper. This avoids stalled downloads through Hugging Face's Xet CDN path on networks where `us.aws.cdn.hf.co/xorbs` has DNS or routing failures.

## Permissions

Grant these permissions to `Vocal.app` after the bundle is built:

- Microphone
- Input Monitoring
- Accessibility (required to auto-paste at the cursor)

### Make Accessibility persist across rebuilds

By default the build signs the bundle ad-hoc. macOS ties the Accessibility grant to a
stable code identity, and an ad-hoc signature's identity (its cdhash) changes on every
rebuild — so the grant you gave silently stops applying and you see
`Accessibility permission is required to paste` again.

Run this **once** to create a stable self-signed code-signing identity:

```bash
./script/create_signing_cert.sh
```

`build_and_run.sh` then signs with that identity automatically. Grant Accessibility to
`Vocal.app` one more time and it will keep working across future rebuilds. macOS may still
require toggling the permission off and on the first time after switching to the stable
identity.

If Accessibility is missing, Vocal does not lose your words: the transcription is left on
the clipboard so you can press **⌘V** to paste it manually, and the app guides you to the
Accessibility pane and auto-recovers the moment access is granted.

## Config

The app creates `~/.config/vocal/config.json` on first run. Relevant fields:

```json
{
  "model": "mlx-community/parakeet-tdt-0.6b-v2",
  "sample_rate": 16000,
  "min_samples": 8000,
  "hotkey": "alt_r",
  "paste_strategy": "clipboard",
  "restore_clipboard": true,
  "python_executable": null
}
```

If needed, set `python_executable` to a specific Python path with `parakeet-mlx` installed.

## Credits

- Transcription by [NVIDIA Parakeet](https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v2) running on [`parakeet-mlx`](https://pypi.org/project/parakeet-mlx/) and Apple's [MLX](https://github.com/ml-explore/mlx).

## License

[MIT](LICENSE) © Kanishq Bansal
