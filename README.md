# Vocal

Vocal is a macOS push-to-talk dictation app. Hold Right Option (or a shortcut of your choice) to record, release to transcribe locally with NVIDIA Parakeet via MLX, then paste the text into the focused app. It runs as a normal Dock app with a window (Home + History) and also keeps a menu-bar item for quick status and actions.

The macOS shell is native Swift/AppKit. The transcription model runs in a long-lived Python daemon because the pinned engine, `parakeet-mlx`, is a Python package.

Everything runs locally — audio never leaves your machine.

## Requirements

- **Apple Silicon Mac (M1 or newer).** Transcription runs on MLX, which is Apple-Silicon only — Intel Macs are not supported.
- **macOS 13 (Ventura) or newer.**
- **Xcode command-line tools** (for building): `xcode-select --install`.

That's it. You do **not** need to install Python — the installer bundles its own.

## Install

One command builds Vocal and installs it into `/Applications` as a fully self-contained app:

```bash
curl -fsSL https://raw.githubusercontent.com/Batmanfi/vocal/main/script/install.sh | bash
```

Or, if you use Claude Code, just tell it:

> install https://github.com/Batmanfi/vocal

The installer clones the repo, builds the native app, embeds its own Python + the
speech-recognition stack **inside the app bundle**, signs it, and drops
`Vocal.app` into `/Applications`. When it finishes you can delete the clone — the
installed app is completely independent.

After installing:

- Open Vocal any time from **Spotlight** (⌘Space → "Vocal") or **Launchpad** — no terminal needed.
- **First launch downloads the speech model (~2.3 GB) once** — the Vocal window shows live download progress — then the app runs fully offline.
- Grant **Microphone**, **Input Monitoring**, and **Accessibility** when prompted (needed to record and paste at your cursor).

Because you build it on your own machine, macOS does not quarantine it — there's no
Gatekeeper "unidentified developer" warning and no Apple notarization required.

It stays in the menu bar, so day-to-day you rarely need to reopen it. To start it
automatically at login, use **Launch at Login** in the menu-bar menu.

### How "self-contained" works

A normal Python virtualenv can't be copied to another Mac — it hardcodes paths and
needs a matching Python already installed. Instead the installer embeds a relocatable
[standalone Python](https://github.com/astral-sh/python-build-standalone) at
`Vocal.app/Contents/Resources/python` and `pip install`s `parakeet-mlx` into it. The
Swift app launches that embedded interpreter (`ParakeetBridge.findPython`), so the
`.app` carries everything it needs — no system Python, no virtualenv, no Homebrew.

The ~2.3 GB model is **not** bundled (it would push the app over 3 GB); it downloads
once on first run into the Hugging Face cache.

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

## Build from source (development)

End users should just run the one-line [installer](#install). This section is for
hacking on Vocal.

```bash
git clone https://github.com/Batmanfi/vocal.git
cd vocal

# fast dev loop: builds dist/Vocal.app against a local venv and launches it
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
./script/build_and_run.sh
```

`build_and_run.sh` is the quick iteration path — it builds the Swift executable and runs
the bundle against the project's `.venv` (it does **not** embed Python, so the app stays
tied to the checkout).

To produce the distributable, self-contained bundle (embedded Python, copy-anywhere):

```bash
./script/package_app.sh     # builds dist/Vocal.app with Python embedded
./script/install.sh         # the above + installs into /Applications
```

On first launch the model downloads into the Hugging Face cache; later launches run
offline. The app sets `HF_HUB_DISABLE_XET=1` for the Parakeet helper to avoid stalled
downloads through Hugging Face's Xet CDN path on networks where `us.aws.cdn.hf.co/xorbs`
has DNS or routing failures.

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

[MIT](LICENSE) © KB
