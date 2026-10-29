# Fix-it Lens

**Point your phone at something broken. It outlines the part, works out what's wrong, then talks you through the repair hands-free, step by step. It stops you if the job is dangerous.**

Fix-it Lens is an iOS app built for the **Meta Global AI Developer Hackathon (26 Oct to 4 Nov 2026)**. Every model call goes to Meta's Model API (`https://api.meta.ai/v1`). Five Meta models are chained into one loop that sees, hears, reasons and guides:

```
 camera / photo ──► SAM 3.1 ──────────► Muse Spark 1.3 ──► Muse Wonder 1.0 ──► Muse Image 1.0
   tap or speak     segment the part    fault + steps      review the plan     exploded-view guide
        ▲               ▲                    │
        │               └── re-segments the part named in each step (mask overlay)
        │                                    ▼
  Muse Voice Transcribe 1.0 ◄── "done" · "go back" · "what's this nut?" ◄── on-device voice reads each step
```

This isn't a single image-to-caption call. Each step's output becomes the next step's input:

- SAM's mask crops the image that Spark reasons over.
- Spark's step `part` names become new SAM prompts for the live highlight.
- Wonder reviews Spark's plan before it is read aloud.
- Muse Voice Transcribe turns the user's voice into navigation or into a grounded question back to Spark.

A local **safety guard** runs before and after every model call.

## What it does

1. **See.** Tap the broken part, or hold the mic and describe it. SAM 3.1 segments exactly that part, using a point prompt from your tap or a concept prompt that Spark extracts from your words.
2. **Diagnose.** Muse Spark 1.3 gets the SAM crop and the whole scene. It returns the object, the part, the fault, the likely cause, a hazard level, tools, and 3 to 7 speakable steps. Each step names one visible part.
3. **Review.** While you read the plan, Muse Wonder 1.0 checks the step order and adds a "make it safe" step. It can raise the hazard but never lower it. In parallel, Muse Image 1.0 draws a technical-manual style illustration.
4. **Guide.** A full-screen, hands-free guide reads each step aloud and spotlights that step's part with a SAM mask. Then it listens. Say *"done"* or *"next"*, *"go back"*, *"say that again"* or *"stop"*, or ask a question such as *"what's this nut?"*. Questions go to Spark together with the photo and the current step. The answer is spoken, and the thing it names is highlighted.
5. **Safety stop.** Some jobs get no steps at all: gas, mains or hard-wired electrics, fuse boxes, sparking or burning smells, refrigerant, microwave or CRT interiors, airbags, fuel or brake-line leaks, and structural damage. You get a clear "call a professional" card and a spoken warning instead. The stop can trigger from what you say, from the model's assessment, or mid-repair ("I can smell gas").

It covers household repairs (sinks, taps, drains, fixtures, furniture), bikes and scooters, and small appliances. It never assesses people, pets, injuries or anything medical.

## 2-minute demo script

Use a real phone with a key in Settings to show the **live** Meta pipeline. **Demo replay** is the no-network backup. It is labelled *Demo replay* in the top pill and plays the same flow from scripted data, so say that it's a replay if you use it.

| Time | Do | Say / show |
|---|---|---|
| 0:00 | Open the app on the lens (onboarding already done). | "Half of all repairs stall at *what is this part and what do I do with it?* Fix-it Lens answers that with five Meta models." |
| 0:12 | Tap the **Leaking sink trap** sample, or point the camera at a real sink. Hold the mic and say *"Why is the pipe under my sink dripping?"* | The status card walks through Muse Voice Transcribe → SAM 3.1 → Muse Spark, and the pipeline rail lights up *See · Hear · Reason · Guide*. The SAM mask appears on the joint. |
| 0:35 | The plan sheet opens. | Point at the fault, the hazard pill (*Caution*: there's a light and socket near the sink) and the confidence meter. Open **Meta API calls**: each row shows the model, its purpose and its latency. The illustration arrives from Muse Image. |
| 0:55 | Tap **Start hands-free guide**. Put the phone down. | Step 1 is spoken and the bucket is spotlighted. Say **"done"**. Step 2 spotlights the slip nut. |
| 1:15 | Ask **"what's this nut?"** | Spark answers in one sentence, and the slip nut is highlighted. |
| 1:30 | Say **"wait, I can smell gas"**. | Everything stops. A red safety card appears and it says *"Stop here. This job needs a qualified professional."* "No model output can talk it out of that. The guard is local and runs before and after every call." |
| 1:45 | Close the guide and tap the **Slipping drive chain** sample. Tap the chain. | Same loop on a vehicle: rear axle nut and chain adjuster highlights. "One pipeline: home, vehicle, appliance." |
| 1:55 | End on the trace card. | "SAM 3.1, Muse Spark, Muse Wonder, Muse Image and Muse Voice Transcribe: all Meta, all in one loop." |

Backup: the **Safety stop demo** sample shows the safety stop in one tap.

## Built during the hackathon

The hackathon runs from 26 Oct to 4 Nov 2026. Everything in this section was built in that window.

**This pass (28 Oct 2026): the Fix-it Lens pivot. This is what the demo shows.**

- The Fix-it Lens product: repair domains, the `RepairPlan` schema, hazard levels and the safety-stop flow.
- The hands-free voice guide (`GuideView`, guide loop in `AppModel`):
  - per-step SAM spotlight, voice-activity end-of-speech detection and voice commands;
  - grounded mid-repair questions with highlight, and mid-repair safety stop.
- `SafetyGuard`, a local hazard filter enforced before and after model calls, and the rule that the hazard is never lowered.
- New prompts for Muse Spark (assessor and guide) and Muse Wonder (reviewer), plus concept extraction for SAM.
- `MetaClient` rewrite:
  - retries with backoff on 429, 5xx and network errors, honouring `Retry-After`;
  - cancellation, error-envelope parsing, `GET /v1/models` and a per-call trace.
- Keychain key storage and a Settings "Test connection" check.
- Demo replay for the two scenes (DemoHome, DemoMachine) plus a safety scene, with no network or key needed.
- The full UI redesign:
  - a design system (night chrome with signal amber and teal, Liquid Glass surfaces);
  - onboarding, lens, plan sheet, guide and settings;
  - Dynamic Type, VoiceOver labels, Reduce Motion, haptics, light, dark and system appearance, and loading, empty and error states.
- App icon and logo drawn with `scripts/generate_icon.py`.
- Tests:
  - Swift Testing suites for voice commands, the safety guard, voice-activity detection, lenient JSON and demo integrity;
  - a replay UI test with screenshots;
  - a live Meta UI test.
- Scripts: `verify_meta_api.py` and `demo_pipeline.py`, rewritten for the Fix-it Lens payloads.

**Later passes (28 Oct 2026):** Fix it together (relay, web helper, in-app session, repair memory), the Ray-Ban Meta glasses camera source with Mock Device, and the demo video project.

**As received (files dated 27 Oct 2026): 

- the SAM 3.1 `one_bit` mask decoder and point-prompt grammar (`SAMParser.swift`), plus its test;
- camera capture, WAV recording for Muse Voice Transcribe, and the original `MetaClient` request shape;
- the two Muse Image demo photos.

## Fix it together (new)

Share a code or link and a friend helps live from the app or any browser. Their tap outlines the part on **both** screens with SAM 3.1; speech goes Muse Voice Transcribe → Muse Spark 1.3 (translation) → captions plus on-device speech, so a Spanish-speaking Fixer and an English-speaking Helper can work together. Muse Spark turns the session into a saved **repair memory** checklist. The safety stop applies inside sessions too.

- **Live:** relay at [`https://fixit-together.joinreson.workers.dev`](https://fixit-together.joinreson.workers.dev/api/health) (Cloudflare Worker + Durable Object, `wss://…/ws/CODE`), web helper at [`https://fixit-lens-together.vercel.app`](https://fixit-lens-together.vercel.app). The app uses this relay by default (Settings can override it).
- All Meta calls run on the Fixer's phone. The relay (Cloudflare Worker + Durable Object, free plan, or `node server.mjs`) only forwards frames and messages and never holds a key.
- Live WebSocket with ack pacing; HTTP snapshot fallback (about 1 frame/s) when WebSockets are blocked.
- Deploy and protocol details: [`together/README.md`](together/README.md). Two-device demo with a scripted helper: **Lens → Fix it together → Two-device demo**, or `together/web/index.html?demo=1&pov=1`.

## Ray-Ban Meta glasses (new)

**Settings → Camera** switches the source between the iPhone camera and Ray-Ban Meta glasses through the **Meta Wearables Device Access Toolkit (DAT) 1.0.1** (`MWDATCore`, `MWDATCamera`, `MWDATMockDevice`, added as a Swift package in the project). The glasses POV feeds the Lens, the voice guide and Fix it together, and spoken audio plays through the glasses (Bluetooth A2DP route).

- **No glasses needed for development or the demo:** DEBUG builds include **Mock Device** (Settings → Camera → Mock Device), which plays the bundled POV clips (`samdevna/Demo/GlassesPOV/`) as the glasses camera. Everything shown with it is labelled *simulated glasses feed*.
- DAT needs **Xcode 26.4+ / Swift 6.3+**. Real glasses need Developer Mode enabled in the Meta AI app; a Wearables Developer Center app ID (`META_APP_ID`) and client token (`CLIENT_TOKEN`, in `Config/Secrets.xcconfig`, gitignored) are only needed for release distribution.
- **Manual step:** merge `Config/InfoPlist-glasses-additions.xml` into `samdevna/Info.plist` (URL scheme `fixitlens`, `MWDAT` dict, Bluetooth and local-network usage strings, background modes, external-accessory protocol).

## Demo video

`fixitlens-demo-v2.mp4` (80 s, 1080×1920, no voiceover, captions on screen; closing line: *Built and tested on Meta's simulated glasses. Live on Ray-Ban Meta at the final.*) is built with Remotion from `demo-video/` (`npm i && npx remotion render FixitLensDemo out/fixitlens-demo.mp4`). What is real and what is not:

- **Real app output:** the Fix it together **web helper** (`together/web`, unchanged code) recorded in its labelled scripted demo with the simulated glasses feed (`HelperCapture` composition, deterministic clock in `public/helper/clock.js`).
- **Recreated, corner-tagged "Concept, simulated glasses feed":** the iPhone screens, drawn from the app's SwiftUI design with demo-replay text. Drop a real screen recording at `public/real/iphone_fixer_together.mp4` and set `IPHONE_RECORDING_READY = true` to use it.
- **Call times** (SAM 3.1 3.8 s, Muse Spark 1.3 6.0 s, Muse Wonder 1.0 10.2 s, Muse Image 1.0 18.6 s, Muse Voice Transcribe 5.0 s) are measured call times from one live run against the Meta API on the developer's Mac (Oct 2026).
- **Concept clips** (AI-generated footage of a person wearing smart glasses), with a small corner tag *Glasses mode, simulated device*: frames 150–269 `public/concept/glasses_wearer_sink.mp4`, frames 1890–2009 `public/concept/glasses_wearer_together.mp4`. Recreated iPhone screens carry a small corner tag *Concept, simulated glasses feed*.

## Judging rubric fit

| Criterion | Weight | Where it shows |
|---|---|---|
| **Impact** | 30 | Small household, bike and appliance repairs for people with no handy friend nearby; Fix it together brings that friend in remotely across languages; a hard safety stop for gas, mains, airbags and similar jobs. |
| **Meta tooling** | 25 | Five Meta models through `api.meta.ai` (SAM 3.1, Muse Spark 1.3, Muse Wonder 1.0, Muse Image 1.0, Muse Voice Transcribe) plus the Meta Wearables DAT SDK for Ray-Ban Meta glasses. Each model has a distinct job (see *Meta API calls*). |
| **Technical depth** | 20 | Parallel pipeline (SAM ‖ Spark on tap; Wonder ‖ Image after the plan), grounded per-step SAM highlights, deterministic local SafetyGuard before and after model calls, a relay protocol with ack pacing, snapshot fallback and shared masks; Swift Testing suites plus relay tests. |
| **Demo** | 25 | 80 s vertical video with every model labelled, timings, the guardrail and the two-device session; demo replay and two-device demo modes work with no key, no network and no glasses, and are labelled as scripted. |

## Meta API calls

| Step | Endpoint | Model | Where |
|---|---|---|---|
| Hear (describe the problem, guide replies) | `POST /v1/asr/transcribe` (multipart: `request` JSON + `audio` WAV, `PUSH_TO_TALK`) | `muse-voice-transcribe-1.0` | `TranscribeService` |
| Speech → part name for SAM | `POST /v1/responses`, `reasoning.effort=minimal` | `muse-spark-1.3` | `RepairBrain.concept` |
| See: segment the tapped / named part | `POST /v1/responses`, point or concept prompt, `metadata.mask_encoding=one_bit` | `sam-3.1` | `SAMService` |
| Diagnose + repair plan (SAM crop + scene) | `POST /v1/responses`, `reasoning.effort=low` | `muse-spark-1.3` | `RepairBrain.assess` |
| Review the plan | `POST /v1/responses`, `reasoning.effort=low` | `muse-wonder-1.0` | `RepairBrain.refine` |
| Illustration | `POST /v1/responses` with the `image_generation` tool | `muse-image-1.0` | `IllustrationService` |
| Highlight each step's part | `POST /v1/responses`, concept prompt | `sam-3.1` | `AppModel.locate` |
| Mid-repair question | `POST /v1/responses`, photo + step context | `muse-spark-1.3` | `RepairBrain.answer` |
| Test connection | `GET /v1/models` | none | Settings |

Steps are read aloud by Apple's on-device `AVSpeechSynthesizer`, because Meta's Model API has no text-to-speech endpoint. That makes no network call.

## Run it

Requirements: Xcode 27 and iOS 27. A device is best, because the simulator has no camera.

1. Open `samdevna.xcodeproj` and pick your team in Signing.
2. Run. With no key, the three samples play in **demo replay**.
3. For the live pipeline, open **Settings → Meta Model API**, paste your key, and tap **Test connection**. The key is stored in the Keychain on the device only.
  

Check every endpoint from a Mac before demoing:

```sh
pip install requests pillow
MODEL_API_KEY=... python3 scripts/verify_meta_api.py
```

Tests: run `⌘U`. The live UI test runs only with `LIVE_META=1` and `MODEL_API_KEY` set in the test scheme.

## Safety, scope and privacy

- **Not for:** gas, mains electrics, refrigerant, airbags, fuel or brake lines, or structural work. Those trigger a stop with no steps. It also never handles people, pets, health or injuries.
- The safety guard is deterministic and local. It runs on your words before any model call, on the model's plan afterwards, and on every reply during the guide. Muse Wonder can raise the hazard but never lower it.
- Photos and voice clips go only to `api.meta.ai` (`store: false` on every Responses call). Nothing else leaves the device: no analytics and no other servers.
- Repair advice can be wrong. The app says so, puts caution steps first, and tells you to stop if anything looks different from the photo.

## Hackathon compliance notes

- Open source: MIT for the app. The SAM mask decoder port is under the SAM License (`LICENSES/SAM-LICENSE.txt`). See `THIRD_PARTY_NOTICES.md` for every asset's provenance.
- No secrets in the repo. `.gitignore` covers `Config/Secrets.xcconfig`, `.env` and `xcuserdata`.
- Team: up to 4 people. Author: Ikechukwu Arum (*add teammates here*).
- Not a banned category. This is a practical repair assistant: no medical advice, no RAG, no coaching, no chatbot. It is a multi-model Meta pipeline with segmentation-grounded voice guidance.

## Project layout

```
samdevna/
  App/            FixitApp (entry), AppModel (pipeline + guide state machine)
  Design/         Theme (palette, type, spacing, motion, haptics), Components
  Features/       Onboarding, Lens (camera, mask overlay), Repair (plan sheet, guide), Together (lobby, session), Settings
  Models/         Repair (plan schema, lenient JSON, errors), Models (SAM types, pipeline/guide state)
  Services/       MetaClient, SAMService, SAMParser, RepairBrain, IllustrationService,
                  TranscribeService, SpeechService, Guidance (SafetyGuard, VoiceIntent, VoiceActivity), Config
  Demo/           DemoLibrary (scripted replay scenes)
samdevnaTests/    Swift Testing + XCTest
samdevnaUITests/  replay walkthrough + live Meta test
scripts/          verify_meta_api.py, demo_pipeline.py, generate_icon.py, generate_brand.py
together/         relay/ (Cloudflare Worker or Node) and web/ (browser helper) for Fix it together
demo-video/       Remotion project for the demo video
```
