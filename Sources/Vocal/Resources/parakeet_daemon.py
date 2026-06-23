#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import traceback

os.environ.setdefault("HF_HUB_DISABLE_XET", "1")


def emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def emit_progress(done: int, total: int) -> None:
    # The Swift side parses these to show first-run model-download progress.
    pct = int(done * 100 / total) if total > 0 else 0
    print(f"PROGRESS\t{pct}\t{done}\t{total}", flush=True)


def _prefetch_model(model_id: str) -> None:
    """Download the model weights up front so we can report progress.

    from_pretrained() fetches config.json + model.safetensors via hf_hub_download
    and shows nothing while the ~GB weights download — on first launch that looks
    like a freeze. We pull the same files here with a tqdm subclass that streams
    PROGRESS lines to stdout, then from_pretrained() loads instantly from cache.
    If anything here fails (offline, API change) we stay silent and let
    from_pretrained() handle the real download/error.
    """
    try:
        from huggingface_hub import hf_hub_download
        from tqdm.std import tqdm as std_tqdm
    except Exception:
        return

    class _ProgressTqdm(std_tqdm):
        def __init__(self, *a, **k):
            self._last_emit = 0.0
            self._last_pct = -1
            super().__init__(*a, **k)
            if self.total:
                emit_progress(0, self.total)

        def update(self, n=1):
            displayed = super().update(n)
            total = self.total or 0
            if total > 0:
                pct = int(self.n * 100 / total)
                now = time.monotonic()
                if pct != self._last_pct and (now - self._last_emit > 0.2 or pct >= 100):
                    self._last_pct = pct
                    self._last_emit = now
                    emit_progress(self.n, total)
            return displayed

    try:
        hf_hub_download(model_id, "config.json")
        hf_hub_download(model_id, "model.safetensors", tqdm_class=_ProgressTqdm)
    except Exception:
        # Best effort; from_pretrained() will surface a real error if needed.
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="mlx-community/parakeet-tdt-0.6b-v2")
    args = parser.parse_args()

    try:
        from parakeet_mlx import from_pretrained

        _prefetch_model(args.model)
        model = from_pretrained(args.model)
        print("READY\tMLX (Apple Silicon)", flush=True)
    except Exception as exc:
        traceback.print_exc(file=sys.stderr)
        emit({"ok": False, "error": f"Model load failed: {exc}"})
        return 1

    for line in sys.stdin:
        audio_path = line.strip()
        if not audio_path:
            continue
        try:
            result = model.transcribe(audio_path)
            emit({"ok": True, "text": getattr(result, "text", "").strip()})
        except Exception as exc:
            traceback.print_exc(file=sys.stderr)
            emit({"ok": False, "error": str(exc)})

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
