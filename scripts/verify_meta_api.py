#!/usr/bin/env python3
"""Smoke-test every Meta Model API call Fix-it Lens makes, with the app's own payloads and prompts.

    MODEL_API_KEY=... python3 scripts/verify_meta_api.py

Reads MODEL_API_KEY (and optional META_BASE_URL) from the environment or a local .env. Never prints the key.
Uses the DemoHome sample (sink trap). Needs `pip install requests pillow`; the voice check needs macOS `say`
or a WAV passed with --wav path/to/clip.wav.
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path

import requests
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "samdevna"
ASSETS = APP / "Assets.xcassets"
PLAN_KEYS = {
    "domain", "object_name", "part_name", "fault", "hazard", "confidence", "tools", "steps", "spoken_intro",
}
UTTERANCE = "Why is the pipe under my sink dripping?"
TAP = (0.54, 0.41)  # DemoLibrary.sink.tapPoint


def load_env() -> tuple[str, str]:
    for p in (ROOT, ROOT.parent):
        env = p / ".env"
        if env.exists():
            for line in env.read_text().splitlines():
                if "=" in line and not line.strip().startswith("#"):
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
            break
    key = os.environ.get("MODEL_API_KEY", "").strip()
    if not key:
        sys.exit("MODEL_API_KEY missing (set it in the environment or a local .env)")
    return key, os.environ.get("META_BASE_URL", "https://api.meta.ai/v1").rstrip("/")


KEY, BASE = load_env()
HEADERS = {"Authorization": f"Bearer {KEY}"}


def swift_prompt(name: str) -> str:
    """Pull a `static let <name> = \"\"\"...\"\"\"` prompt out of RepairBrain.swift so the script never drifts."""
    src = (APP / "Services" / "RepairBrain.swift").read_text()
    body = re.search(rf'static let {name} = """\n(.*?)\n    """', src, re.S).group(1)
    body = re.sub(r"\\\n\s*", "", body)  # Swift line continuations
    return "\n".join(line[4:] if line.startswith("    ") else line for line in body.splitlines())


def responses(model: str, body: dict) -> dict:
    r = requests.post(f"{BASE}/responses", headers=HEADERS, json=dict(body, model=model, store=False), timeout=240)
    if r.status_code >= 400:
        raise RuntimeError(f"HTTP {r.status_code}: {r.text[:600]}")
    return r.json()


def output_text(data: dict) -> str:
    if data.get("output_text"):
        return data["output_text"]
    return "\n".join(
        part["text"] for item in data.get("output") or [] for part in item.get("content") or [] if part.get("text")
    )


def json_of(raw: str) -> dict:
    return json.loads(raw[raw.index("{"): raw.rindex("}") + 1])


def jpeg_data_url(png: Path, max_edge: int) -> tuple[str, int, int]:
    img = Image.open(png).convert("RGB")
    img.thumbnail((max_edge, max_edge))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=82)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode(), img.width, img.height


def spoken_wav(text: str, wav_path: str | None) -> bytes:
    """24 kHz mono 16-bit PCM, the way WAVWriter.mono16 writes it."""
    with tempfile.TemporaryDirectory() as tmp:
        if wav_path:
            src_path = Path(wav_path)
        elif shutil.which("say") and shutil.which("afconvert"):
            aiff, src_path = Path(tmp) / "q.aiff", Path(tmp) / "q.wav"
            subprocess.run(["say", "-o", str(aiff), text], check=True)
            subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@24000", "-c", "1", str(aiff), str(src_path)], check=True)
        else:
            raise RuntimeError("skipped: no --wav given and macOS `say` is not available")
        with wave.open(str(src_path)) as src:
            frames, rate, channels, width = src.readframes(src.getnframes()), src.getframerate(), src.getnchannels(), src.getsampwidth()
        if channels != 1 or width != 2:
            raise RuntimeError("WAV must be mono 16-bit")
        clean = Path(tmp) / "clean.wav"
        with wave.open(str(clean), "wb") as dst:
            dst.setnchannels(1)
            dst.setsampwidth(2)
            dst.setframerate(rate)
            dst.writeframes(frames)
        return clean.read_bytes()


def check(name: str, fn) -> bool:
    start = time.time()
    try:
        detail = fn()
        print(f"PASS  {name}  ({time.time() - start:.1f}s)\n      {detail}\n", flush=True)
        return True
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL  {name}  ({time.time() - start:.1f}s)\n      {exc}\n", flush=True)
        return False


STOP_CATEGORIES = {
    "gas": r"\b(gas|lpg|propane|butane|carbon monoxide)\b",
    "mains_electrics": r"\b(mains|fuse ?box|breaker (panel|box)|consumer unit|live wir(e|es|ing)|exposed (live )?wir(e|es|ing)|hard[- ]?wired|high voltage|\d{3} ?v(olts?)?|sparking|sparks|burning smell)\b",
    "refrigerant": r"\b(refrigerant|magnetron|microwave (inside|interior|capacitor)|crt)\b",
    "airbags": r"\b(airbags?|srs module)\b",
    "fuel_or_brake_leak": r"\b(fuel (line|leak|tank leak)|petrol leak|diesel leak|brake (line|hose|fluid) leak|leaking brake (line|fluid))\b",
    "structural": r"\b(structural crack|load[- ]bearing|ceiling (is )?sagging)\b",
}
PROXIMITY = r"\b(near|nearby|next to|close to|beside|above|below|under|around|away from)\b"
ORDER = {"none": 0, "caution": 1, "stop": 2}


def merge_review(original: dict, reviewed: dict) -> dict:
    """Python mirror of PlanReview.merge (Guidance.swift): never drop steps; stop only for a real category."""
    o_h = str(original.get("hazard", "caution")).lower()
    r_h = str(reviewed.get("hazard", o_h)).lower()
    merged = dict(original)
    if o_h == "stop":
        return merged
    if r_h == "stop":
        cat = str(reviewed.get("stop_category", "")).lower().replace(" ", "_").replace("-", "_")
        reason = str(reviewed.get("hazard_reason", ""))
        named = {c for c, rx in STOP_CATEGORIES.items() if re.search(rx, reason, re.I)}
        proximity_only = bool(re.search(PROXIMITY, reason, re.I)) and named <= {"mains_electrics"}
        if cat in STOP_CATEGORIES and cat in named and not proximity_only:
            merged.update(hazard="stop", stop_category=cat, hazard_reason=reason, steps=[])
            return merged
        r_h = "caution"
    steps = [s for s in reviewed.get("steps") or [] if isinstance(s, dict) and s.get("instruction")]
    if steps and len(steps) * 2 >= len(original.get("steps") or []):
        merged["steps"] = steps
    merged["hazard"] = max(o_h, r_h, key=lambda h: ORDER.get(h, 1))
    return merged


SAM_RECORD = re.compile(r"(\d+)<\|box;([^|]+)\|><\|mask;([^|]+)\|>")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wav", help="mono 16-bit WAV to send to ASR instead of macOS `say`")
    args = parser.parse_args()

    photo = ASSETS / "DemoHome.imageset" / "DemoHome.png"
    sam_url, w, h = jpeg_data_url(photo, 1280)
    brain_url, _, _ = jpeg_data_url(photo, 768)
    results: list[bool] = []
    plan: dict = {}
    timings: dict = {}

    def models() -> str:
        r = requests.get(f"{BASE}/models", headers=HEADERS, timeout=30)
        if r.status_code >= 400:
            raise RuntimeError(f"HTTP {r.status_code}: {r.text[:300]}")
        ids = {m.get("id") for m in r.json().get("data", [])}
        wanted = {"sam-3.1", "muse-spark-1.3", "muse-wonder-1.0", "muse-image-1.0", "muse-voice-transcribe-1.0"}
        return f"{len(ids)} models; app models listed: {sorted(wanted & ids)}; not listed: {sorted(wanted - ids) or 'none'}"

    results.append(check("KEY   GET /v1/models", models))

    def sam(prompt: str) -> str:
        data = responses("sam-3.1", {
            "input": [{"type": "message", "role": "user", "content": [
                {"type": "input_text", "text": prompt},
                {"type": "input_image", "image_url": sam_url},
            ]}],
            "metadata": {"mask_encoding": "one_bit", "include_confidence": "true"},
        })
        text = output_text(data)
        records = SAM_RECORD.findall(text)
        if text and not records:
            raise RuntimeError(f"unparseable SAM output: {text[:200]}")
        boxes = [dict(kv.split("=", 1) for kv in r[1].split(";")) for r in records]
        return f"{len(records)} object(s); first box {boxes[0] if boxes else 'none'}"

    results.append(check("SEE   sam-3.1 point prompt (tap on the sink trap)", lambda: sam(
        f"<0f>1<|point;x={int(w * TAP[0])};y={int(h * TAP[1])};w={w};h={h}|>")))
    results.append(check("SEE   sam-3.1 concept prompt ('slip nut', fallback only)", lambda: sam("slip nut")))

    def transcribe() -> str:
        settings = {
            "mode": "PUSH_TO_TALK", "model": "muse-voice-transcribe-1.0", "audioEncoding": "WAV",
            "languageBias": ["English"], "keywords": ["slip nut", "P-trap", "washer", "chain", "sprocket", "done"],
        }
        r = requests.post(
            f"{BASE}/asr/transcribe", headers={**HEADERS, "Accept": "application/json"},
            files={
                "request": (None, json.dumps(settings), "application/json"),
                "audio": ("utterance.wav", spoken_wav(UTTERANCE, args.wav), "audio/wav"),
            },
            timeout=120,
        )
        if r.status_code >= 400:
            raise RuntimeError(f"HTTP {r.status_code}: {r.text[:600]}")
        transcript = r.json().get("transcript", "").strip()
        if not transcript:
            raise RuntimeError(f"empty transcript: {r.text[:300]}")
        return f"heard: {transcript}"

    results.append(check("HEAR  muse-voice-transcribe-1.0 (POST /v1/asr/transcribe, WAV)", transcribe))

    # The app's tap path: SAM 3.1 point prompt and Muse Spark start together (Spark gets a close-up around the
    # tap plus the scene with an amber ring), so the plan does not wait for the mask.
    def close_up_and_scene() -> tuple[str, str]:
        img = Image.open(photo).convert("RGB")
        img.thumbnail((768, 768))
        side = int(min(img.size) * 0.42)
        cx, cy = int(TAP[0] * img.width), int(TAP[1] * img.height)
        x0 = min(max(cx - side // 2, 0), img.width - side)
        y0 = min(max(cy - side // 2, 0), img.height - side)
        crop = img.crop((x0, y0, x0 + side, y0 + side))
        scene = img.copy()
        from PIL import ImageDraw
        r = int(max(scene.size) * 0.035)
        ImageDraw.Draw(scene).ellipse((cx - r, cy - r, cx + r, cy + r), outline=(255, 176, 32), width=max(3, int(r * 0.18)))
        def url(im: Image.Image, q: int) -> str:
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=q)
            return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
        return url(crop, 80), url(scene, 70)

    def assess() -> str:
        from concurrent.futures import ThreadPoolExecutor
        close_url, scene_url = close_up_and_scene()
        body = {
            "instructions": swift_prompt("assessor"),
            "input": [{"type": "message", "role": "user", "content": [
                {"type": "input_text", "text": (
                    f"Domain: home.\nThe user tapped at x={TAP[0]:.2f}, y={TAP[1]:.2f} (amber ring on the scene). "
                    "The first image is a close-up around that point.\nReply language: English.\n"
                    f"User said: {UTTERANCE}\nWrite JSON only."
                )},
                {"type": "input_image", "image_url": close_url},
                {"type": "input_image", "image_url": scene_url},
            ]}],
            "reasoning": {"effort": "low"},
        }
        start = time.time()
        with ThreadPoolExecutor(2) as pool:
            def timed_sam():
                try:
                    return sam(f"<0f>1<|point;x={int(w * TAP[0])};y={int(h * TAP[1])};w={w};h={h}|>"), time.time() - start
                except Exception as exc:  # noqa: BLE001 (reported, but the plan check is about Spark)
                    return f"SAM failed: {exc}", time.time() - start
            sam_future = pool.submit(timed_sam)
            spark_future = pool.submit(lambda: (responses("muse-spark-1.3", body), time.time() - start))
            data, spark_s = spark_future.result()
            sam_text, sam_s = sam_future.result()
        parsed = json_of(output_text(data))
        if str(parsed.get("hazard", "")).lower() not in {"none", "caution", "stop"}:
            raise RuntimeError(f"hazard '{parsed.get('hazard')}' would decode leniently, check the prompt")
        plan.update(parsed)
        missing = PLAN_KEYS - parsed.keys()
        steps = parsed.get("steps") or []
        located = sum(1 for st in steps if isinstance(st, dict) and (st.get("point") or st.get("box")))
        timings["plan_visible"] = spark_s
        print("      steps:", flush=True)
        for i, st in enumerate(steps, 1):
            if isinstance(st, dict):
                print(f"        {i}. {st.get('title')} | part {st.get('part')!r} | point {st.get('point')} box {st.get('box')}", flush=True)
        return (f"fault: {parsed.get('fault')} | hazard {parsed.get('hazard')} | {len(steps)} steps, {located} located | "
                f"parallel: SAM {'mask' if not sam_text.startswith('SAM failed') else 'FAILED'} at {sam_s:.1f}s, plan visible at {spark_s:.1f}s | missing keys: {sorted(missing) or 'none'}")

    results.append(check("THINK muse-spark-1.3 plan (close-up + scene) in parallel with sam-3.1 point", assess))

    def step_points() -> str:
        """Guide highlights: a SAM point prompt at each step's Spark-estimated location (fallback: concept text)."""
        out = []
        for st in plan.get("steps") or []:
            if not isinstance(st, dict) or not st.get("part"):
                continue
            pt = st.get("point")
            if isinstance(pt, dict):
                pt = [pt.get("x"), pt.get("y")]
            if not (isinstance(pt, list) and len(pt) == 2 and all(isinstance(v, (int, float)) for v in pt)):
                box = st.get("box")
                if isinstance(box, list) and len(box) == 4:
                    pt = [(box[0] + box[2]) / 2, (box[1] + box[3]) / 2]
                else:
                    out.append(f"{st['part']}: no point")
                    continue
            scale = 1000 if max(pt) > 100 else (100 if max(pt) > 1 else 1)
            x, y = pt[0] / scale, pt[1] / scale
            res = sam(f"<0f>1<|point;x={int(w * x)};y={int(h * y)};w={w};h={h}|>")
            out.append(f"{st['part']}@({x:.2f},{y:.2f}): {res.split(';')[0]}")
        if not out:
            raise RuntimeError("no located steps")
        return " | ".join(out)

    results.append(check("SEE   sam-3.1 point prompts at Spark's per-step locations", step_points))

    def refine() -> str:
        if not plan:
            raise RuntimeError("skipped: no plan to review")
        data = responses("muse-wonder-1.0", {
            "instructions": swift_prompt("reviewer"),
            "input": (
                'Reply in English. Keep JSON keys and every "part" in English.\nInput plan JSON:\n'
                + json.dumps(plan, ensure_ascii=False) + "\nReturn the same JSON schema, improved."
            ),
            "reasoning": {"effort": "low"},
        })
        parsed = json_of(output_text(data))
        merged = merge_review(plan, parsed)
        raw = f"raw review: {len(parsed.get('steps') or [])} steps, hazard {parsed.get('hazard')}, category {parsed.get('stop_category')!r}"
        # The sink is ordinary plumbing: after the app's merge it must stay non-stop with steps.
        if merged["hazard"] == "stop" or not merged["steps"]:
            raise RuntimeError(f"sink was stopped or lost its steps after merge ({raw})")
        return f"{raw} -> merged: hazard {merged['hazard']}, {len(merged['steps'])} steps"

    results.append(check("THINK muse-wonder-1.0 safety review (sink must stay non-stop with steps)", refine))

    def answer() -> str:
        data = responses("muse-spark-1.3", {
            "instructions": swift_prompt("guide"),
            "input": [{"type": "message", "role": "user", "content": [
                {"type": "input_text", "text": (
                    f"Object: {plan.get('object_name', 'sink trap')}. Fault: {plan.get('fault', 'leaking joint')}.\n"
                    "Current step 2 of 5: Loosen the slip nut.\nReply language: English.\nQuestion: what's this nut?"
                )},
                {"type": "input_image", "image_url": brain_url},
            ]}],
            "reasoning": {"effort": "low"},
        })
        parsed = json_of(output_text(data))
        return f"answer: {parsed.get('answer')} | highlight: {parsed.get('highlight')!r} | point: {parsed.get('point')} | stop: {parsed.get('safety_stop')}"

    results.append(check("GUIDE muse-spark-1.3 mid-repair question", answer))

    def illustrate() -> str:
        data = responses("muse-image-1.0", {
            "input": [{"type": "message", "role": "user", "content": [
                {"type": "input_text", "text": (
                    (plan.get("illustration_prompt") or "Exploded-view repair illustration: re-seating a leaking sink trap slip nut.")
                    + "\nStyle: clean technical manual illustration, dark charcoal background, signal-amber highlights, "
                      "large readable labels in English, no brand logos, no people's faces."
                )},
                {"type": "input_image", "image_url": brain_url},
            ]}],
            "tools": [{
                "type": "image_generation", "enable_web_search": False, "enable_shell": True,
                "reasoning_strength": "low", "size": "1024x1024", "output_format": "png",
            }],
        })
        for item in data.get("output") or []:
            if item.get("type") == "image_generation_call" and item.get("result"):
                out = ROOT / "output" / "verify_illustration.png"
                out.parent.mkdir(exist_ok=True)
                out.write_bytes(base64.b64decode(item["result"]))
                return f"image saved to {out.relative_to(ROOT)}"
        raise RuntimeError(f"no image in response: {json.dumps(data)[:300]}")

    results.append(check("SHOW  muse-image-1.0 repair illustration", illustrate))

    passed = sum(results)
    if timings.get("plan_visible"):
        print(f"Tap path: plan visible after {timings['plan_visible']:.1f}s (Spark in parallel with SAM; review and image run after)")
    print(f"{passed}/{len(results)} Meta API checks passed")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
