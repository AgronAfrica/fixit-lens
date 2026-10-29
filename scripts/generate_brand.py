#!/usr/bin/env python3
"""Regenerate the two Fix-it Lens demo stills (DemoHome, DemoMachine) through Muse Image 1.0.

The app icon and logo are drawn locally by scripts/generate_icon.py (no model involved).
Usage: python3 scripts/generate_brand.py [DemoHome] [DemoMachine]
"""

from __future__ import annotations

import base64
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "samdevna" / "Assets.xcassets"
KEY = os.environ.get("MODEL_API_KEY", "").strip()
BASE = os.environ.get("META_BASE_URL", "https://api.meta.ai/v1").rstrip("/")

JOBS = [
    {
        "name": "DemoHome",
        "path": ASSETS / "DemoHome.imageset" / "DemoHome.png",
        "size": "1024x1536",
        "prompt": (
            "Photoreal vertical iPhone photo of a leaking PVC pipe joint under a "
            "modest Indian kitchen sink. Slow drip, mineral white stains, wet floor "
            "tile, plastic bucket, indoor tungsten plus window light. Authentic, "
            "slightly messy, real home. No text, no watermark."
        ),
    },
    {
        "name": "DemoMachine",
        "path": ASSETS / "DemoMachine.imageset" / "DemoMachine.png",
        "size": "1024x1536",
        "prompt": (
            "Photoreal vertical iPhone photo of a worn motorcycle drive chain and "
            "sprocket on a commuter bike in an Indian roadside workshop. Rust, "
            "dry slack links, grease, daylight, concrete floor, authentic. "
            "No text, no watermark, no brand logos."
        ),
    },
]


def load_dotenv() -> None:
    env_path = next((p / ".env" for p in (ROOT, ROOT.parent) if (p / ".env").exists()), None)
    if env_path is None:
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())


def generate(job: dict) -> str:
    prompt = job["prompt"]
    payload = {
        "model": "muse-image-1.0",
        "input": prompt,
        "tools": [
            {
                "type": "image_generation",
                "enable_web_search": False,
                "enable_image_search": False,
                "enable_shell": False,
                "reasoning_strength": "low",
                "size": job["size"],
                "output_format": "png",
            }
        ],
    }
    r = requests.post(
        f"{BASE}/responses",
        headers={
            "Authorization": f"Bearer {KEY}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=240,
    )
    if r.status_code >= 400:
        raise RuntimeError(f"{job['name']} HTTP {r.status_code}: {r.text[:800]}")
    data = r.json()
    result_b64 = None
    for item in data.get("output") or []:
        if item.get("type") == "image_generation_call" and item.get("result"):
            result_b64 = item["result"]
            break
    if not result_b64:
        raise RuntimeError(f"{job['name']} missing image: {json.dumps(data)[:800]}")
    raw = base64.b64decode(result_b64)
    dest: Path = job["path"]
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(raw)
    return f"{job['name']} -> {dest} ({len(raw)} bytes)"


def main() -> int:
    load_dotenv()
    global KEY, BASE
    KEY = os.environ.get("MODEL_API_KEY", "").strip()
    BASE = os.environ.get("META_BASE_URL", "https://api.meta.ai/v1").rstrip("/")
    if not KEY:
        print("MODEL_API_KEY missing", file=sys.stderr)
        return 1
    names = set(sys.argv[1:] or [j["name"] for j in JOBS])
    jobs = [j for j in JOBS if j["name"] in names]
    errors = []
    with ThreadPoolExecutor(max_workers=min(4, len(jobs))) as pool:
        futs = {pool.submit(generate, j): j["name"] for j in jobs}
        for fut in as_completed(futs):
            name = futs[fut]
            try:
                print(fut.result(), flush=True)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{name}: {exc}")
                print(errors[-1], file=sys.stderr, flush=True)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
