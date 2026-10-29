import React from "react";
import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Video } from "@remotion/media";
import { C, FONT, MONO, IPHONE_RECORDING_READY } from "./theme";
import { ConceptLabel, Outline, Phone, PovVideo, Sheet, SinkPhoto, StatusBar, Tag, Title, coverBox, fadeIn, rise } from "./ui";

const SINK = { w: 1280, h: 1920 };
const POV = { w: 504, h: 896 };
const JOINT: [number, number, number, number] = [0.43, 0.34, 0.65, 0.49];
const NUT: [number, number, number, number] = [0.52, 0.42, 0.64, 0.49];
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

// ---------------------------------------------------------------- 1. Hook (0–5 s)
export const Hook: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const a = rise(f, fps, 0), b = rise(f, fps, 42), d = rise(f, fps, 80);
  return (
    <AbsoluteFill style={{ background: C.night }}>
      <Img src={staticFile("img/sink.png")} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover", opacity: 0.28, filter: "blur(6px)", scale: String(interpolate(f, [0, 150], [1.08, 1.0])) }} />
      <AbsoluteFill style={{ padding: "230px 70px", gap: 50 }}>
        <div style={{ opacity: a, transform: `translateY(${(1 - a) * 40}px)`, color: C.text, fontFamily: FONT, fontSize: 84, fontWeight: 900, lineHeight: 1.05 }}>
          How many repairs do we pay for that we could do in <span style={{ color: C.amber }}>10 minutes?</span>
        </div>
        <div style={{ opacity: b, transform: `translateY(${(1 - b) * 30}px)`, display: "flex", alignItems: "center", gap: 26 }}>
          <Img src={staticFile("img/icon.png")} style={{ width: 120, height: 120, borderRadius: 28 }} />
          <div style={{ color: C.text, fontFamily: FONT, fontSize: 44, fontWeight: 700, lineHeight: 1.2 }}>
            <span style={{ color: C.teal }}>Fix-it Lens</span>: point your phone, or Ray-Ban Meta glasses, at what's broken. It shows you the fix.
          </div>
        </div>
        <div style={{ opacity: d, transform: `translateY(${(1 - d) * 30}px)`, color: C.dim, fontFamily: FONT, fontSize: 40, lineHeight: 1.3 }}>
          For renters, students and first-time homeowners: anyone without a handy friend nearby.
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- 2. Tap → SAM 3.1 (9–17 s)
export const TapScene: React.FC = () => {
  const f = useCurrentFrame();
  const tap = coverBox(SINK.w, SINK.h, [0.54, 0.41, 0.54, 0.41]);
  const ripple = interpolate(f, [40, 70], [0, 1], clamp);
  const outline = interpolate(f, [78, 96], [0, 1], clamp);
  const sheet = interpolate(f, [120, 140], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ background: C.night }}>
      <Title kicker="1 · LENS" title="Point, then tap the part" top={70} />
      <ConceptLabel style={{ top: 238 }} extra="Recreated iPhone screen · outline placed as in the app's demo replay" />
      <Phone width={560} x={248} y={340}>
        <SinkPhoto />
        <StatusBar title="Fix-it Lens" chip="Camera: iPhone" />
        {f >= 40 ? (
          <div style={{ position: "absolute", left: tap.left - 40, top: tap.top - 40, width: 80, height: 80, borderRadius: 40,
            border: `3px solid ${C.text}`, opacity: 1 - ripple, transform: `scale(${0.4 + ripple})` }} />
        ) : null}
        <Outline rect={coverBox(SINK.w, SINK.h, JOINT)} label="leaking pipe joint" progress={outline} />
        <Sheet height={200} progress={sheet}>
          <div style={{ fontSize: 13, fontFamily: MONO, color: C.amber, fontWeight: 700 }}>sam-3.1 · muse-spark-1.3</div>
          <div style={{ fontSize: 22, fontWeight: 800, marginTop: 6 }}>Outlining the part you tapped</div>
          <div style={{ fontSize: 16, color: C.dim, marginTop: 6 }}>Diagnosing in parallel…</div>
        </Sheet>
      </Phone>
      <div style={{ position: "absolute", left: 0, right: 0, top: 1600, display: "flex", justifyContent: "center", opacity: outline }}>
        <Tag color={C.amber} size={30}>SAM 3.1 · point-prompt segmentation</Tag>
      </div>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- 3. Parallel pipeline (17–27 s)
const LANES = [
  { group: "On tap, in parallel", rows: [
    { model: "SAM 3.1", job: "Mask of the tapped part", s: 3.8, color: C.amber },
    { model: "Muse Spark 1.3", job: "Diagnosis + step plan", s: 6.0, color: C.teal },
  ] },
  { group: "After the plan is shown, in parallel", rows: [
    { model: "Muse Wonder 1.0", job: "Second-opinion safety review", s: 10.2, color: C.sky },
    { model: "Muse Image 1.0", job: "Illustration of the step", s: 18.6, color: C.coral },
  ] },
];
const MAX_S = 18.6;

export const PipelineScene: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const plan = interpolate(f, [120, 140], [0, 1], clamp);
  let row = 0;
  return (
    <AbsoluteFill style={{ background: C.night }}>
      <Title kicker="2 · PARALLEL PIPELINE" title="Plan in about 6 seconds" top={70} />
      <ConceptLabel style={{ top: 238 }} extra="Recreated iPhone screen · plan text from the app's demo replay" />
      <Phone width={430} x={40} y={340}>
        <SinkPhoto />
        <StatusBar title="Fix-it Lens" chip="Plan ready" />
        <Outline rect={coverBox(SINK.w, SINK.h, JOINT)} label="leaking pipe joint" progress={1} />
        <Sheet height={470} progress={plan}>
          <div style={{ fontSize: 13, fontFamily: MONO, color: C.teal, fontWeight: 700 }}>muse-spark-1.3 · reviewing with muse-wonder-1.0…</div>
          <div style={{ fontSize: 24, fontWeight: 800, marginTop: 6 }}>Slip joint on the trap is leaking</div>
          <div style={{ fontSize: 15, color: C.dim, marginTop: 4 }}>Sink waste trap · easy · about 15 min · confidence 82%</div>
          {["Catch the drips", "Find the leaking joint", "Hand-tighten the slip nut", "Reseat the washer", "Test it"].map((s, i) => (
            <div key={s} style={{ display: "flex", gap: 10, alignItems: "center", marginTop: 12, opacity: fadeIn(f, 140 + i * 6, 8) }}>
              <div style={{ width: 26, height: 26, borderRadius: 13, background: C.teal, color: "#111", fontWeight: 800, fontSize: 14, display: "flex", alignItems: "center", justifyContent: "center" }}>{i + 1}</div>
              <div style={{ fontSize: 18, fontWeight: 600 }}>{s}</div>
            </div>
          ))}
          <div style={{ marginTop: 16, padding: "8px 10px", borderRadius: 10, border: `1px dashed ${C.coral}`, color: C.coral, fontSize: 13, opacity: fadeIn(f, 170) }}>
            muse-image-1.0 · drawing step illustration…
          </div>
        </Sheet>
      </Phone>
      <div style={{ position: "absolute", left: 510, right: 40, top: 360, display: "flex", flexDirection: "column", gap: 26 }}>
        {LANES.map((lane, li) => (
          <div key={lane.group} style={{ opacity: fadeIn(f, li * 110, 12) }}>
            <div style={{ color: C.dim, fontFamily: MONO, fontSize: 22, marginBottom: 14 }}>{lane.group}</div>
            {lane.rows.map((r) => {
              const start = li * 110 + 10 + (row++ % 2) * 4;
              const p = interpolate(f, [start, start + 40 + (r.s / MAX_S) * 60], [0, 1], clamp);
              return (
                <div key={r.model} style={{ marginBottom: 22 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
                    <div style={{ color: r.color, fontFamily: FONT, fontSize: 32, fontWeight: 800 }}>{r.model}</div>
                    <div style={{ color: C.text, fontFamily: MONO, fontSize: 30, fontWeight: 700 }}>{(r.s * p).toFixed(1)} s</div>
                  </div>
                  <div style={{ color: C.dim, fontFamily: FONT, fontSize: 24, margin: "4px 0 10px" }}>{r.job}</div>
                  <div style={{ height: 18, borderRadius: 9, background: "rgba(255,255,255,0.08)" }}>
                    <div style={{ height: 18, borderRadius: 9, width: `${(r.s / MAX_S) * 100 * p}%`, background: r.color }} />
                  </div>
                </div>
              );
            })}
          </div>
        ))}
        <div style={{ opacity: fadeIn(f, 200), padding: 18, borderRadius: 16, border: `1px solid ${C.line}`, background: C.panel }}>
          <div style={{ color: C.text, fontFamily: FONT, fontSize: 26, fontWeight: 700, lineHeight: 1.3 }}>You start fixing while the review and the drawing finish.</div>
          <div style={{ color: C.dim, fontFamily: FONT, fontSize: 21, marginTop: 10, lineHeight: 1.35 }}>Measured call times from one live run against the Meta API on the developer's Mac (Oct 2026). Bar lengths are to scale.</div>
        </div>
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: 1610, textAlign: "center", color: C.dim, fontFamily: MONO, fontSize: 22, opacity: fadeIn(f, 20) }}>
        {`t = ${interpolate(f, [0, 300], [0, 10], clamp).toFixed(1)} s in this scene · ${fps} fps`}
      </div>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- 4. Voice guide (27–35 s)
export const VoiceScene: React.FC = () => {
  const f = useCurrentFrame();
  const heard = fadeIn(f, 40), ans = fadeIn(f, 110), hl = interpolate(f, [110, 128], [0, 1], clamp);
  const talking = f > 10 && f < 40;
  return (
    <AbsoluteFill style={{ background: C.night }}>
      <Title kicker="3 · VOICE GUIDE" title="Ask out loud, hands busy" top={70} />
      <ConceptLabel style={{ top: 238 }} extra="Recreated iPhone screen · answer text from the app's demo replay" />
      <Phone width={520} x={40} y={340}>
        <SinkPhoto />
        <StatusBar title="Step 3 of 5" chip="Guide on" />
        <Outline rect={coverBox(SINK.w, SINK.h, NUT)} label="slip nut" progress={hl} />
        <Sheet height={330}>
          <div style={{ fontSize: 13, fontFamily: MONO, color: C.amber, fontWeight: 700 }}>Hand-tighten the slip nut</div>
          <div style={{ fontSize: 17, color: C.dim, marginTop: 6 }}>Grip this large plastic nut and turn it clockwise, as seen from above, until it's snug.</div>
          <div style={{ marginTop: 14, padding: "10px 12px", borderRadius: 14, background: "rgba(90,180,255,0.14)", opacity: heard, fontSize: 18 }}>
            <b>You:</b> “What's this nut?”
          </div>
          <div style={{ marginTop: 10, padding: "10px 12px", borderRadius: 14, background: "rgba(52,209,176,0.14)", opacity: ans, fontSize: 18, lineHeight: 1.3 }}>
            That's the slip nut. It squeezes a washer against the pipe to seal the joint. Turn it clockwise by hand.
          </div>
        </Sheet>
        <div style={{ position: "absolute", right: 20, bottom: 350, width: 70, height: 70, borderRadius: 35, background: talking ? C.coral : C.amber,
          display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28, transform: `scale(${talking ? 1.1 : 1})` }}>🎙</div>
      </Phone>
      <div style={{ position: "absolute", left: 610, right: 40, top: 420, display: "flex", flexDirection: "column", gap: 30 }}>
        {[
          { t: 40, color: C.sky, a: "Muse Voice Transcribe", b: "Speech to text · 5.0 s measured" },
          { t: 80, color: C.teal, a: "Muse Spark 1.3", b: "Answers about the current step and names the part" },
          { t: 110, color: C.amber, a: "SAM 3.1", b: "Re-outlines the part it named" },
          { t: 140, color: C.text, a: "On-device speech", b: "iOS AVSpeechSynthesizer reads the answer (no Meta TTS)" },
        ].map((r) => (
          <div key={r.a} style={{ opacity: fadeIn(f, r.t), borderLeft: `6px solid ${r.color}`, paddingLeft: 18 }}>
            <div style={{ color: r.color, fontFamily: FONT, fontSize: 34, fontWeight: 800 }}>{r.a}</div>
            <div style={{ color: C.dim, fontFamily: FONT, fontSize: 25, marginTop: 6, lineHeight: 1.3 }}>{r.b}</div>
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- 5. Safety stop (35–42 s)
export const SafetyScene: React.FC = () => {
  const f = useCurrentFrame();
  const stop = interpolate(f, [50, 66], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ background: C.night }}>
      <Title kicker="4 · GUARDRAIL" title="Some jobs it will not help with" top={70} />
      <ConceptLabel style={{ top: 238 }} extra="Recreated iPhone screen · wording is the app's real SafetyGuard text" />
      <Phone width={520} x={40} y={340}>
        <SinkPhoto />
        <div style={{ position: "absolute", inset: 0, background: `rgba(40,4,4,${0.85 * stop})` }} />
        <StatusBar title="Fix-it Lens" chip={stop > 0.5 ? "Safety stop" : "Listening"} chipColor={stop > 0.5 ? C.coral : C.teal} />
        <div style={{ position: "absolute", left: 20, right: 20, top: 120, padding: "10px 12px", borderRadius: 14, background: "rgba(90,180,255,0.18)", fontSize: 19, opacity: fadeIn(f, 10) }}>
          <b>You:</b> “I can smell gas near the boiler.”
        </div>
        <div style={{ position: "absolute", left: 20, right: 20, top: 250, opacity: stop, transform: `translateY(${(1 - stop) * 30}px)` }}>
          <div style={{ width: 70, height: 70, borderRadius: 16, background: C.coral, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 40, fontWeight: 900, color: "#fff" }}>!</div>
          <div style={{ fontSize: 34, fontWeight: 900, marginTop: 18 }}>Stop here.</div>
          <div style={{ fontSize: 19, marginTop: 10, lineHeight: 1.35 }}>This job needs a qualified professional. Please don't touch it, and call a licensed engineer or electrician.</div>
          <div style={{ fontSize: 16, color: "rgba(255,255,255,0.75)", marginTop: 14, lineHeight: 1.35 }}>Gas appliances and pipework must only be worked on by a registered gas engineer. If you smell gas, leave the area and call your gas emergency line.</div>
          <div style={{ marginTop: 18, fontSize: 14, fontFamily: MONO, color: C.coral }}>No repair steps are shown.</div>
        </div>
      </Phone>
      <div style={{ position: "absolute", left: 610, right: 40, top: 420, display: "flex", flexDirection: "column", gap: 30 }}>
        {[
          { t: 30, a: "On-device rules first", b: "The transcript is checked before any plan. Gas, mains electrics, refrigerant, airbags, fuel or brake leaks, structural damage." },
          { t: 90, a: "Models can only raise it", b: "Muse Spark 1.3 or Muse Wonder 1.0 can flag a stop; a stop plan never carries steps." },
          { t: 140, a: "Same rule in Fix it together", b: "The session shows a safety banner for both people." },
        ].map((r) => (
          <div key={r.a} style={{ opacity: fadeIn(f, r.t), borderLeft: `6px solid ${C.coral}`, paddingLeft: 18 }}>
            <div style={{ color: C.text, fontFamily: FONT, fontSize: 32, fontWeight: 800 }}>{r.a}</div>
            <div style={{ color: C.dim, fontFamily: FONT, fontSize: 24, marginTop: 6, lineHeight: 1.3 }}>{r.b}</div>
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- 6. Fix it together (42–63 s)
// Mirrors the scripted demo session in together/web/demo.js, which the helper capture records.
const FIXER_FEED = [
  { at: 1.6, who: "You", text: "Hay agua goteando debajo del fregadero.", sub: "→ helper sees: There's water dripping under the sink." },
  { at: 6.6, who: "You", text: "Ya veo la tuerca. ¿La giro a la derecha?", sub: "→ I can see the nut. Do I turn it to the right?" },
  { at: 10.9, who: "Helper", text: "Gira la tuerca en el sentido del reloj, a mano, y luego un cuarto más.", sub: "spoken in the glasses" },
  { at: 15.5, who: "Helper", text: "Genial. Abre el grifo un minuto y revisa si gotea.", sub: "spoken in the glasses" },
];

export const TogetherScene: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = f / fps;
  const mask = interpolate(t, [4.45, 4.8], [0, 1], clamp);
  const memory = interpolate(t, [17.0, 17.5], [0, 1], clamp);
  const shown = FIXER_FEED.filter((c) => t >= c.at).slice(-2);
  return (
    <AbsoluteFill style={{ background: C.night }}>
      <Title kicker="5 · FIX IT TOGETHER" title="Help live, in any language" top={60} />
      {/* Left: Fixer iPhone, recreated, fed by the Mock Device glasses clip */}
      <div style={{ position: "absolute", left: 24, top: 236, width: 500, textAlign: "center" }}>
        <div style={{ color: C.text, fontFamily: FONT, fontSize: 26, fontWeight: 800 }}>Fixer · iPhone + glasses</div>
        <div style={{ color: C.dim, fontFamily: FONT, fontSize: 18, fontWeight: 600, marginTop: 4 }}>Concept, simulated glasses feed</div>
        <div style={{ color: C.dim, fontFamily: FONT, fontSize: 18, marginTop: 2 }}>{IPHONE_RECORDING_READY ? "iPhone screen recording" : "Recreated screen · Mock Device clip"}</div>
      </div>
      {IPHONE_RECORDING_READY ? (
        <div style={{ position: "absolute", left: 24, top: 340, width: 500, height: 1083, borderRadius: 40, overflow: "hidden" }}>
          <Video src={staticFile("real/iphone_fixer_together.mp4")} muted objectFit="cover" style={{ width: "100%", height: "100%" }} />
        </div>
      ) : (
        <Phone width={476} x={24} y={340}>
          <PovVideo />
          <StatusBar title="Together · 4F7-K2Q" chip="Mock glasses · 12 fps" />
          <Outline rect={coverBox(POV.w, POV.h, NUT)} label="Helper: slip nut" progress={mask} dashed />
          <div style={{ position: "absolute", left: 14, right: 14, bottom: 30, display: "flex", flexDirection: "column", gap: 8 }}>
            {memory > 0 ? (
              <div style={{ opacity: memory, padding: "8px 12px", borderRadius: 12, background: "rgba(52,209,176,0.2)", border: `1px solid ${C.teal}`, fontSize: 14 }}>
                <span style={{ fontFamily: MONO, color: C.teal, fontWeight: 700 }}>muse-spark-1.3</span> · Repair memory saved: “Fix a dripping sink trap” (4 steps)
              </div>
            ) : null}
            {shown.map((c) => (
              <div key={c.at} style={{ padding: "8px 12px", borderRadius: 12, background: "rgba(10,12,16,0.88)", opacity: fadeIn(t * fps, c.at * fps, 8) }}>
                <div style={{ fontSize: 12, fontFamily: MONO, color: C.sky }}>{c.who} · muse-voice-transcribe → muse-spark</div>
                <div style={{ fontSize: 16, fontWeight: 700, marginTop: 2 }}>{c.text}</div>
                <div style={{ fontSize: 12, color: C.dim, marginTop: 2 }}>{c.sub}</div>
              </div>
            ))}
          </div>
        </Phone>
      )}
      {/* Right: the REAL web helper client, recorded from together/web */}
      <div style={{ position: "absolute", left: 530, top: 236, width: 530, textAlign: "center" }}>
        <div style={{ color: C.text, fontFamily: FONT, fontSize: 26, fontWeight: 800 }}>Helper · any browser</div>
        <div style={{ color: C.teal, fontFamily: FONT, fontSize: 20, fontWeight: 700, marginTop: 4 }}>Real web client, scripted demo session</div>
        <div style={{ color: C.dim, fontFamily: FONT, fontSize: 18, marginTop: 2 }}>together/web · fed the same simulated glasses clip</div>
      </div>
      <div style={{ position: "absolute", left: 530, top: 350, width: 530, height: 942, borderRadius: 28, overflow: "hidden", border: `2px solid ${C.line}` }}>
        <Video src={staticFile("real/helper_web_capture.mp4")} muted objectFit="cover" style={{ width: "100%", height: "100%" }} />
      </div>
      <div style={{ position: "absolute", left: 530, top: 1312, width: 530, display: "flex", flexDirection: "column", gap: 12, alignItems: "flex-start" }}>
        <Tag color={C.amber} size={21}>tap → SAM 3.1 mask on both screens</Tag>
        <Tag color={C.sky} size={21}>Muse Voice Transcribe → Muse Spark 1.3</Tag>
        <Tag color={C.teal} size={21}>captions + speech, Spanish ⇄ English</Tag>
        <Tag color={C.dim} size={21}>Meta keys stay on the Fixer's phone</Tag>
      </div>
      <div style={{ position: "absolute", left: 24, right: 24, top: 1560, color: C.dim, fontFamily: FONT, fontSize: 21, lineHeight: 1.35, textAlign: "center" }}>
        In a live session the outline and captions come from SAM 3.1, Muse Voice Transcribe and Muse Spark on the Fixer's phone; here they are the labelled demo script.
      </div>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- 7. Built on 5 Meta models (67–74 s)
const MODELS = [
  { name: "SAM 3.1", job: "Segments the part you tap, on both screens", color: C.amber },
  { name: "Muse Spark 1.3", job: "Diagnosis, step plan, answers, translation", color: C.teal },
  { name: "Muse Wonder 1.0", job: "Second-opinion safety review", color: C.sky },
  { name: "Muse Image 1.0", job: "Illustrates the current step", color: C.coral },
  { name: "Muse Voice Transcribe", job: "Speech to text for the guide and Together", color: "#C59BFF" },
];
export const ModelsScene: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill style={{ background: C.night, padding: "150px 70px" }}>
      <div style={{ color: C.text, fontFamily: FONT, fontSize: 76, fontWeight: 900, opacity: rise(f, fps) }}>Built on <span style={{ color: C.amber }}>5 Meta models</span></div>
      <div style={{ display: "flex", flexDirection: "column", gap: 26, marginTop: 60 }}>
        {MODELS.map((m, i) => {
          const p = rise(f, fps, 12 + i * 10);
          return (
            <div key={m.name} style={{ opacity: p, transform: `translateX(${(1 - p) * 80}px)`, padding: "26px 30px", borderRadius: 22, background: C.panel, borderLeft: `10px solid ${m.color}` }}>
              <div style={{ color: m.color, fontFamily: FONT, fontSize: 44, fontWeight: 800 }}>{m.name}</div>
              <div style={{ color: C.dim, fontFamily: FONT, fontSize: 30, marginTop: 6 }}>{m.job}</div>
            </div>
          );
        })}
      </div>
      <div style={{ marginTop: 40, color: C.dim, fontFamily: FONT, fontSize: 28, lineHeight: 1.4, opacity: fadeIn(f, 80) }}>
        All through api.meta.ai. Plus the Meta Wearables Device Access Toolkit 1.0.1 for the glasses camera (Mock Device in this demo).
      </div>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------- 8. End card (74–80 s)
export const EndCard: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = rise(f, fps);
  return (
    <AbsoluteFill style={{ background: C.night, alignItems: "center", justifyContent: "center", gap: 36, padding: 80, textAlign: "center" }}>
      <Img src={staticFile("img/icon.png")} style={{ width: 240, height: 240, borderRadius: 54, opacity: p, transform: `scale(${0.8 + 0.2 * p})` }} />
      <div style={{ color: C.text, fontFamily: FONT, fontSize: 96, fontWeight: 900, opacity: p }}>Fix-it Lens</div>
      <div style={{ color: C.amber, fontFamily: FONT, fontSize: 46, fontWeight: 700, opacity: fadeIn(f, 15) }}>Point. Tap. Fix it, or fix it together.</div>
      <div style={{ color: C.dim, fontFamily: FONT, fontSize: 30, lineHeight: 1.45, opacity: fadeIn(f, 35), maxWidth: 900 }}>
        Open source · built during the Meta Global AI Developer Hackathon 2026
      </div>
      <div style={{ color: C.text, fontFamily: FONT, fontSize: 34, fontWeight: 700, lineHeight: 1.35, opacity: fadeIn(f, 45), maxWidth: 900 }}>
        Built and tested on Meta's simulated glasses. Live on Ray-Ban Meta at the final.
      </div>
      <div style={{ color: C.dim, fontFamily: FONT, fontSize: 20, lineHeight: 1.45, opacity: fadeIn(f, 60), maxWidth: 920 }}>
        iPhone screens recreated with demo-replay content · web helper recorded in its scripted demo · call times from one live API run.
      </div>
    </AbsoluteFill>
  );
};
