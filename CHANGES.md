# CHANGES

Dates: **as received**, meaning the SAVE/SAMVEDNA files dated 27 Oct 2026, and **this pass**, meaning 28 Oct 2026. Both are inside the hackathon window (26 Oct to 4 Nov 2026). Everything below is from this pass unless it is marked *kept*.

## 1. Product pivot: SAVE/SAMVEDNA → Fix-it Lens

- **Removed:** every health, first-aid and crop-diagnosis flow and prompt. That includes `BrainService` ("heal" prompts), `TeacherService`, `HealSheet`, `Features/Heal/`, the `DemoCrop` sample, `HealReport`/`HealDomain`/`Severity` and the `SAVEApp` entry point.
  - Reason: the hackathon bans AI medical advice. The old assessor prompt also covered people and plants.
- **New domain:**
  - `Models/Repair.swift` defines `RepairDomain` (home/vehicle/appliance), `Hazard` (none/caution/stop), `RepairStep` (title, instruction, `part` to highlight, tool, caution) and `RepairPlan`.
  - Decoding is lenient: confidence given as a string or a percentage, a single string where a list is expected, and steps given as plain strings.
  - `ModelJSON` pulls JSON out of fenced or prose replies. A prose-only reply becomes a plan with **no invented steps**.
  - `GuideAnswer` and `FixError` (friendly 401/403/429 messages) live here too.
- **New name:** "Fix-it Lens" for the display name, prompts, Keychain service, usage strings and onboarding. The bundle id `com.codewithik.samdevna` and the Xcode target `samdevna` are kept so signing still works.

## 2. Meta API: every call audited

| # | Purpose | Endpoint | Model | Code |
|---|---|---|---|---|
| 1 | Transcribe the user's description and replies in the guide | `POST https://api.meta.ai/v1/asr/transcribe` (multipart: `request` JSON `{mode: PUSH_TO_TALK, model, audioEncoding: WAV, languageBias, keywords}` + `audio` 24 kHz mono 16-bit WAV) | `muse-voice-transcribe-1.0` | `TranscribeService.transcribe` → `MetaClient.transcribeWAV` |
| 2 | Speech → one noun phrase for SAM | `POST /v1/responses`, `reasoning.effort = minimal` | `muse-spark-1.3` | `RepairBrain.concept` |
| 3 | Segment the tapped point | `POST /v1/responses`, `<0f>1<\|point;x=;y=;w=;h=\|>` + image, `metadata {mask_encoding: one_bit, include_confidence: "true"}` | `sam-3.1` | `SAMService.object(at:in:)` |
| 4 | Segment a named part (from speech, or each guide step's `part`) | same, with a concept text prompt | `sam-3.1` | `SAMService.best` (in `AppModel.listen` and `AppModel.locate`) |
| 5 | Fault + repair plan from the SAM crop + whole scene | `POST /v1/responses`, `instructions = Prompts.assessor`, 2 `input_image`s, `reasoning.effort = low` | `muse-spark-1.3` | `RepairBrain.assess` |
| 6 | Review the plan (order, a make-safe step, speakable wording; hazard never lowered) | `POST /v1/responses`, `reasoning.effort = low` | `muse-wonder-1.0` | `RepairBrain.refine` |
| 7 | Exploded-view illustration | `POST /v1/responses`, `tools: [{type: image_generation, enable_web_search: false, enable_shell: true, reasoning_strength: low, size: 1024x1024, output_format: png}]`. Result is base64 in `output[].type == image_generation_call` | `muse-image-1.0` | `IllustrationService` |
| 8 | Answer a spoken question mid-repair, with an optional highlight and safety stop | `POST /v1/responses`, photo + step context, `reasoning.effort = low` | `muse-spark-1.3` | `RepairBrain.answer` |
| 9 | Key check ("Test connection") | `GET /v1/models` | none | `MetaClient.listModels` (Settings) |

Every request goes to `https://api.meta.ai/v1` with `Authorization: Bearer <key>`; every `/v1/responses` body also carries `store: false`. No endpoint was invented. All of them are the ones the project already used, or `GET /v1/models` from Meta's API reference (used only for the key check).

**Non-Meta calls found and how each was fixed**

- **Glimmer TTS** (`GLIMMER_BASE_URL`, a self-hosted text-to-speech server on the local network). This was the only non-Meta network call.
  - **Removed** completely: the client, the settings fields, `GLIMMER_BASE_URL` in Info.plist and the xcconfig, and `NSAllowsLocalNetworking`.
  - Speech output now uses Apple's on-device `AVSpeechSynthesizer`, because Meta's Model API has no TTS endpoint. That isn't a network call.
- No other hosts. There are no analytics or third-party SDKs.

**MetaClient (rewritten; request shapes kept):**

- An `actor` with a single `send` path.
- Up to 3 attempts on 429, 5xx and transient `URLError`s, with exponential backoff that honours `Retry-After` (capped at 8 s).
- Task cancellation maps to `CancellationError`, so it is never shown as a failure.
- Meta's `{error: {message}}` envelope is parsed. A 401/403/429 gets a human message.
- `MetaTrace` records each call (model, purpose, attempt, status, latency) for the in-app "Meta API calls" card.
- Multipart ASR keeps the original field names.

## 3. Pipeline, concurrency and errors

- `AppModel` (MainActor) runs one replaceable pipeline task. **Cancel** and **Retry** are on the status card, and Retry re-runs the exact failed action.
- Live voice flow:
  1. ASR.
  2. Local `SafetyGuard` pre-check, which stops before any model call.
  3. Spark concept, then SAM best match.
  4. Spark assess on the SAM crop and the scene, then `SafetyGuard.enforce`.
  5. The plan is presented and the intro spoken.
  6. Wonder refine and Muse Image run **in parallel** in a task group. Each is optional, and the plan stays usable if either fails.
- JPEG encoding is done off the main actor (`Task.detached`).
- Camera: a double-capture guard, one-time configuration, and resume on the session queue.
- Going to the background stops the mic but doesn't kill an in-flight diagnosis.
- `SpeechService.say()` is `async` and resumes when the utterance finishes or is cancelled (continuation keyed per utterance, with a cancellation handler).
- `TranscribeService`:
  - `listenOnce()` uses `VoiceActivity` (adaptive noise floor, end after 1.1 s of silence, give up after 7 s with no speech, 15 s cap);
  - clips under 0.35 s are dropped;
  - the audio tap is built in a nonisolated context with a locked accumulator. The original `installThrowingTap` wrapper is *kept*.

## 4. Hands-free guide (new)

- `GuideView` is a full-screen view. For each step it:
  1. locates the step's `part` with SAM (cached per concept);
  2. spotlights it on the photo, dimming everything else;
  3. reads the step aloud, then listens for a reply.
- `VoiceIntent` parses the reply: next/done (multilingual), back, repeat, stop, or a question. Questions go to Spark. The spoken answer can highlight a new part.
- Mid-repair safety: any reply matching `SafetyGuard` raises a red stop banner and a spoken warning, and ends guidance.
- Buttons and chips mirror every voice command. The idle timer is disabled while the guide is open. Hands-free can be turned off in Settings.

## 5. Safety stop (new)

- `Services/Guidance.swift` → `SafetyGuard`: deterministic regex rules covering:
  - gas, LPG, propane, butane and CO;
  - mains, fuse box or breaker, consumer unit, live or exposed wiring, hard-wired circuits, high voltage, and 3-digit voltages;
  - sparking and burning smells;
  - refrigerant, microwave or CRT interiors;
  - airbags, fuel leaks and brake-line leaks;
  - structural damage.
- Tested so that "spark plug", "gasket" and "chain" do **not** trigger it.
- It runs on the transcript before any call, on the plan after Spark, and on each guide reply. `enforce` clears the steps on a stop.
- Wonder's reviewed plan can raise the hazard but never lower it.
- Prompts refuse people, animals, injuries, medicine or anything medical.

## 6. Demo mode (new)

- `Demo/DemoLibrary.swift` has three scripted scenes on the two Muse Image stills. Each has a plan, normalised part regions, scripted answers and a suggested question.
  - **Leaking sink trap** (`DemoHome`): 5 steps.
  - **Slipping drive chain** (`DemoMachine`): 6 steps.
  - **Safety stop demo** (`DemoHome` + "I can smell gas near the boiler").
- Replay runs when "Demo replay" is on, or when there is no key. It never opens the mic or the network, and it is clearly labelled *Demo replay* in the UI and the trace card.
- With a key and replay off, the same samples go through the **live** pipeline.

## 7. Design (rewritten UI)

- **Theme** (`Design/Theme.swift`):
  - Night chrome (#06070A) with signal amber (#FFB020) for "the part", teal for "OK" and coral for "stop".
  - Adaptive light and dark surfaces, with an appearance setting (System/Dark/Light).
  - Rounded Dynamic Type scale, a spacing and radius scale, and motion presets that respect **Reduce Motion**.
  - Semantic haptics.
- **Components:**
  - Liquid Glass surfaces (`glassEffect`), primary and secondary buttons, icon buttons with accessibility labels, pills, a pulsing status dot and a confidence meter;
  - shimmer loading, empty states, a spotlight cutout and a flow layout.
- **Lens:** a camera or photo stage with an amber SAM mask overlay (dashed for demo regions), tap ripple, scan sweep and coach reticle.
  - Domain picker, status card with cancel/retry, a "See · Hear · Reason · Guide" pipeline rail, a sample strip, shutter/retake/plan controls, and a hold-to-talk mic with a live level.
- **Plan sheet:** fault header with hazard pill, safety-stop or caution card, steps, "you'll need" and "don't" lists, illustration (shimmer while it loads), Meta call trace and share.
- **Onboarding:** 4 pages (See, Think, Talk, Safety) on an animated mesh gradient, with Skip.
- **Settings:**
  - Keychain API key with save/remove and **Test connection** (`GET /v1/models`);
  - demo replay, hands-free, language, speaking speed with a preview, and appearance;
  - a scope/safety section and the pipeline list.
- **Accessibility:** VoiceOver labels and identifiers on every control, decorative images hidden, Dynamic Type everywhere, and no colour-only status.
- **App icon and logo:** new, drawn from primitives by `scripts/generate_icon.py` (lens ring, hex nut, teal SAM contour). The received icon and logo were replaced because their provenance was unknown.
- SAM overlay colours recoloured to amber in `SAMParser`. The decoder itself is *kept*.

## 8. Secrets and config

- The API key is stored in the **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
  - Lookup order: Keychain, then the Info.plist build value (placeholders ignored), then the `MODEL_API_KEY` environment variable (tests).
  - The legacy `UserDefaults` key is migrated and then deleted.
- New `Config/App.xcconfig` (committed, empty key) `#include?`s the gitignored `Config/Secrets.xcconfig`. The project's base configuration now points to `App.xcconfig`, so a fresh clone builds without secrets.
- `Secrets.example.xcconfig` has an empty placeholder and a warning that a key set there is compiled into the bundle.
- Info.plist: display name "Fix-it Lens" and new camera, microphone and photo usage strings. Glimmer and local networking are removed. `INFOPLIST_KEY_CFBundleDisplayName` is updated to match.

## 9. Tests

- `samdevnaTests/SAMParserTests.swift` (*kept*: mask decode, corrupt mask, point grammar, fill transform). The lenient decode test now targets `ModelJSON.plan`, and there is a new test for demo-region pixel mapping.
- `samdevnaTests/samdevnaTests.swift` (new, Swift Testing) covers voice commands, safety stop (stops and non-stops), `enforce`, voice-activity end of speech, lenient plan and answer JSON, and demo integrity (every step and answer highlight resolves to a region inside the image; the safety scene stops).
- `samdevnaUITests` has two tests:
  - a replay walkthrough: sink sample → tap → plan → guide → next → question → gas stop, with screenshots attached;
  - a safety-sample test.
  - The live Meta test is skipped unless `LIVE_META=1`.
- Verified on Linux (Swift 6.0.3): every Swift file parses, and the Foundation-only logic (`Repair.swift`, `Guidance.swift`, `DemoLibrary.swift`) compiles and passes 58 checks. **Not verified here:** an Xcode build and running the XCTest suites, because no macOS toolchain was available. Run `⌘U` before submitting.

## 10. Scripts and docs

- `scripts/verify_meta_api.py`, rewritten:
  - checks `GET /v1/models`, SAM point and concept, ASR, Spark concept, Spark assess, Wonder review, the Spark guide answer and Muse Image;
  - uses the DemoHome photo and **reads the prompts straight from `RepairBrain.swift`**;
  - uses Pillow instead of `sips`, and takes `--wav` instead of macOS `say`.
- `scripts/demo_pipeline.py`, rewritten as a CLI for the full pipeline on any still.
- `scripts/generate_brand.py` now regenerates only the two demo stills (the crop and icon jobs are removed).
- `scripts/generate_icon.py` is new. `write_placeholder_png.py` no longer writes the crop placeholder.
- New `README.md` (pitch, 2-minute demo script, "Built during the hackathon", API table, setup, safety), `LICENSE` (MIT), `THIRD_PARTY_NOTICES.md`, `LICENSES/SAM-LICENSE.txt` and `.gitignore`.

## 11. Open doubts and risks

- **`enable_shell: true`** on the Muse Image tool is kept exactly as the project had it, and the old brand script used `false`. The flag isn't needed for illustration, so consider `false` if Meta's docs allow it.
- **Bundled key:** any key set in `Secrets.xcconfig` ends up in Info.plist inside the .ipa. Use the Keychain path for shared builds.
- **SafetyGuard is English-keyword based.** For other reply languages it relies on the model's own `hazard: stop` and the never-lower rule.
- **Asset rights:**
  - The demo stills are Muse Image outputs (XMP `trainedAlgorithmicMedia`). Confirm that the Meta API output terms allow a public repo and video.
  - `SAMParser`'s decoder is a SAM License derivative, so that licence is included.
- **Timeline:** confirm that the received SAVE code was started on or after 26 Oct. If not, list those parts as pre-existing in the README.
- `output/` (an old verify image) is gitignored and excluded from the zip.


---

# CHANGES v2 (28 Oct 2026, later passes)

## 12. Fix it together (new)
- In-app session: `Services/Together/` (protocol, transport with WebSocket + HTTP snapshot fallback and ack pacing, session state, repair memory store, mask tracker) and `Features/Together/` (lobby with join code/link, QR share sheet, two-device demo; live session view with shared SAM masks, captions with model tags, hold-to-talk, safety banner, save to repair memory).
- `AppModel`: start/join/end sessions, `fixitlens://` and `/j/CODE` links, frames routed to the session only while one is open, replay of a saved memory.
- `together/relay`: Cloudflare Worker + Durable Object relay (free plan) and an equivalent Node server; `npm test` protocol tests (5/5 pass). No model calls and no keys on the relay.
- `together/web`: browser helper (no install), scripted demo mode `?demo=1` (and `&pov=1` for the simulated glasses feed), `vercel.json`. Fixed: the `?demo=1` auto-start crashed (temporal dead zone on `canvas`); the canvas now resizes with its stage, so taps map to the right part once captions appear.

## 13. Ray-Ban Meta glasses via DAT SDK 1.0.1 (new)
- `Services/Glasses/` (`CameraSource`, `GlassesCameraService`): registration through the Meta AI app, glasses camera stream, snapshot, Mock Device (DEBUG) fed with `Demo/GlassesPOV/*.mp4`.
- Settings → Camera source switch; Lens, the guide and Fix it together take the glasses POV; audio session allows Bluetooth A2DP so speech plays in the glasses.
- `project.pbxproj`: Swift package `facebook/meta-wearables-dat-ios` exact 1.0.1 with `MWDATCore`, `MWDATCamera`, `MWDATMockDevice`.
- `Config/App.xcconfig`: empty `META_APP_ID` / `CLIENT_TOKEN` (set in gitignored `Secrets.xcconfig`).
- **Manual step:** merge `Config/InfoPlist-glasses-additions.xml` into `samdevna/Info.plist` (it was not edited automatically).

## 14. Demo video (new)
- `demo-video/`: Remotion project. `FixitLensDemo` (80 s, 1080x1920) and `HelperCapture` (records the real web helper with a deterministic clock). See README → *Demo video* for what is real, recreated and concept.

## 15. Docs and tests
- README: *Fix it together*, *Ray-Ban Meta glasses*, *Demo video*, *Judging rubric fit*; `together/README.md` with deploy steps.
- `samdevnaTests/TogetherTests.swift` (codes and links, frame packing, message round trips, pacer, tracker). Linux harness: 39/39 checks pass; all Swift files parse. Not built in Xcode here (DAT needs Xcode 26.4+ / Swift 6.3+).

## Changed files since the first zip (`samdevna-redesigned.zip`)
```
MODIFIED 28
M Config/App.xcconfig
M README.md
M samdevna.xcodeproj/project.pbxproj
M samdevna/App/AppModel.swift
M samdevna/App/FixitApp.swift
M samdevna/Demo/DemoLibrary.swift
M samdevna/Design/Components.swift
M samdevna/Design/Theme.swift
M samdevna/Features/Lens/LensView.swift
M samdevna/Features/Lens/MaskOverlay.swift
M samdevna/Features/Onboarding/OnboardingView.swift
M samdevna/Features/Repair/GuideView.swift
M samdevna/Features/Repair/RepairSheet.swift
M samdevna/Features/Settings/SettingsView.swift
M samdevna/Models/Models.swift
M samdevna/Models/Repair.swift
M samdevna/Services/AudioSession.swift
M samdevna/Services/CameraService.swift
M samdevna/Services/Config.swift
M samdevna/Services/Guidance.swift
M samdevna/Services/IllustrationService.swift
M samdevna/Services/MetaClient.swift
M samdevna/Services/RepairBrain.swift
M samdevna/Services/SAMService.swift
M samdevna/Services/SpeechService.swift
M samdevna/Services/TranscribeService.swift
M samdevnaUITests/samdevnaUITests.swift
M scripts/verify_meta_api.py
ADDED 63
A Config/InfoPlist-glasses-additions.xml
A demo-video/.gitignore
A demo-video/README.md
A demo-video/package-lock.json
A demo-video/package.json
A demo-video/remotion.config.ts
A demo-video/src/HelperCapture.tsx
A demo-video/src/Root.tsx
A demo-video/src/demo/Main.tsx
A demo-video/src/demo/captions.ts
A demo-video/src/demo/scenes.tsx
A demo-video/src/demo/theme.ts
A demo-video/src/demo/timeline.ts
A demo-video/src/demo/ui.tsx
A demo-video/src/index.ts
A demo-video/tsconfig.json
A samdevna/Demo/GlassesPOV/demo-bike.jpg
A samdevna/Demo/GlassesPOV/demo-sink.jpg
A samdevna/Demo/GlassesPOV/glasses_pov_bike.mp4
A samdevna/Demo/GlassesPOV/glasses_pov_sink.mp4
A samdevna/Features/Together/TogetherLobby.swift
A samdevna/Features/Together/TogetherView.swift
A samdevna/Services/Glasses/CameraSource.swift
A samdevna/Services/Glasses/GlassesCameraService.swift
A samdevna/Services/Together/TogetherLogic.swift
A samdevna/Services/Together/TogetherProtocol.swift
A samdevna/Services/Together/TogetherSession.swift
A samdevna/Services/Together/TogetherTransport.swift
A samdevnaTests/PlanReviewTests.swift
A samdevnaTests/TogetherTests.swift
A together/README.md
A together/relay/package-lock.json
A together/relay/package.json
A together/relay/server.mjs
A together/relay/src/room.js
A together/relay/src/worker.js
A together/relay/test/relay.test.mjs
A together/relay/wrangler.toml
A together/web/app.js
A together/web/config.js
A together/web/demo-bike.jpg
A together/web/demo-pov-sink.mp4
A together/web/demo-sink.jpg
A together/web/demo.js
A together/web/icon.png
A together/web/index.html
A together/web/lib.js
A together/web/style.css
A together/web/vercel.json
A demo-video/public/** (14 asset files)
REMOVED 0
```
