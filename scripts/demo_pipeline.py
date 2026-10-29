#!/usr/bin/env python3
"""Run the Fix-it Lens pipeline on any still, outside the app:
SAM 3.1 (see) -> Muse Spark 1.3 (fault + plan) -> Muse Wonder 1.0 (review) -> Muse Image 1.0 (illustration).

    python3 scripts/demo_pipeline.py --image photo.jpg --part "leaking pipe joint" --utterance "Why is this dripping?"

Writes sam.txt, plan.json, reviewed.json and illustration.png to output/pipeline/. Never prints the API key.
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from pathlib import Path

from verify_meta_api import json_of, jpeg_data_url, output_text, responses, swift_prompt  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--part", default="leaking pipe joint", help="SAM 3.1 concept prompt")
    parser.add_argument("--utterance", default="Why is this dripping?")
    parser.add_argument("--domain", default="home", choices=["home", "vehicle", "appliance"])
    parser.add_argument("--out", default=str(ROOT / "output" / "pipeline"))
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    image_url, _, _ = jpeg_data_url(Path(args.image), 1024)

    print("SEE    sam-3.1", flush=True)
    sam = responses("sam-3.1", {
        "input": [{"type": "message", "role": "user", "content": [
            {"type": "input_text", "text": args.part}, {"type": "input_image", "image_url": image_url}]}],
        "metadata": {"mask_encoding": "one_bit", "include_confidence": "true"},
    })
    (out / "sam.txt").write_text(output_text(sam))

    print("THINK  muse-spark-1.3", flush=True)
    plan = json_of(output_text(responses("muse-spark-1.3", {
        "instructions": swift_prompt("assessor"),
        "input": [{"type": "message", "role": "user", "content": [
            {"type": "input_text", "text": (
                f"Domain: {args.domain}.\nSAM 3.1 segmented: {args.part}.\nReply language: English.\n"
                f"User said: {args.utterance}\nWrite JSON only.")},
            {"type": "input_image", "image_url": image_url}]}],
        "reasoning": {"effort": "low"},
    })))
    (out / "plan.json").write_text(json.dumps(plan, indent=2, ensure_ascii=False))
    print(f"       {plan.get('fault')}  (hazard: {plan.get('hazard')})")
    if str(plan.get("hazard")).lower() == "stop":
        print(f"SAFETY STOP: {plan.get('hazard_reason')}")
        return 0

    print("REVIEW muse-wonder-1.0", flush=True)
    reviewed = json_of(output_text(responses("muse-wonder-1.0", {
        "instructions": swift_prompt("reviewer"),
        "input": ('Reply in English. Keep JSON keys and every "part" in English.\nInput plan JSON:\n'
                  + json.dumps(plan, ensure_ascii=False) + "\nReturn the same JSON schema, improved."),
        "reasoning": {"effort": "low"},
    })))
    (out / "reviewed.json").write_text(json.dumps(reviewed, indent=2, ensure_ascii=False))
    for i, step in enumerate(reviewed.get("steps") or [], 1):
        print(f"       {i}. {step.get('title') if isinstance(step, dict) else step}")

    print("SHOW   muse-image-1.0", flush=True)
    image = responses("muse-image-1.0", {
        "input": [{"type": "message", "role": "user", "content": [
            {"type": "input_text", "text": (reviewed.get("illustration_prompt") or plan.get("illustration_prompt") or args.part)
             + "\nStyle: clean technical manual illustration, dark charcoal background, signal-amber highlights."},
            {"type": "input_image", "image_url": image_url}]}],
        "tools": [{"type": "image_generation", "enable_web_search": False, "enable_shell": True,
                   "reasoning_strength": "low", "size": "1024x1024", "output_format": "png"}],
    })
    for item in image.get("output") or []:
        if item.get("type") == "image_generation_call" and item.get("result"):
            (out / "illustration.png").write_bytes(base64.b64decode(item["result"]))
            print(f"       saved {out / 'illustration.png'}")
            break
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
