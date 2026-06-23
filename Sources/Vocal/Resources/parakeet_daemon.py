#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import traceback

os.environ.setdefault("HF_HUB_DISABLE_XET", "1")


def emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="mlx-community/parakeet-tdt-0.6b-v2")
    args = parser.parse_args()

    try:
        from parakeet_mlx import from_pretrained

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
