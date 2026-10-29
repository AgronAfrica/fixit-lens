import React from "react";
import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig, spring } from "remotion";
import { Video } from "@remotion/media";
import { C, FONT, MONO } from "./theme";
import { CAPTIONS } from "./captions";

export const fadeIn = (frame: number, start = 0, len = 12) =>
  interpolate(frame, [start, start + len], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

export const rise = (frame: number, fps: number, delay = 0) =>
  spring({ frame: frame - delay, fps, config: { damping: 200 }, durationInFrames: 18 });

/** A model or fact tag, e.g. "SAM 3.1". */
export const Tag: React.FC<{ color?: string; children: React.ReactNode; size?: number; style?: React.CSSProperties }> = ({ color = C.amber, children, size = 26, style }) => (
  <div style={{
    display: "inline-flex", alignItems: "center", gap: 10, padding: `${size * 0.35}px ${size * 0.7}px`,
    borderRadius: 999, border: `2px solid ${color}`, background: "rgba(6,7,10,0.82)", color,
    fontFamily: MONO, fontSize: size, fontWeight: 700, whiteSpace: "nowrap", ...style,
  }}>{children}</div>
);

/** Small corner tag on every shot that is not real app output. */
export const CornerTag: React.FC<{ text: string; sub?: string }> = ({ text, sub }) => (
  <div style={{ position: "absolute", top: 28, right: 28, display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 4, zIndex: 50 }}>
    <div style={{ padding: "6px 14px", borderRadius: 999, background: "rgba(6,7,10,0.55)", border: "1px solid rgba(255,255,255,0.22)",
      color: "rgba(244,246,250,0.85)", fontFamily: FONT, fontWeight: 600, fontSize: 19, letterSpacing: 0.2 }}>{text}</div>
    {sub ? <div style={{ color: "rgba(244,246,250,0.5)", fontFamily: FONT, fontSize: 15, paddingRight: 8 }}>{sub}</div> : null}
  </div>
);

/** iPhone-screen shots: recreated from the app design, fed by the simulated glasses/camera image. */
export const ConceptLabel: React.FC<{ extra?: string; style?: React.CSSProperties }> = ({ extra }) => (
  <CornerTag text="Concept, simulated glasses feed" sub={extra ? "Recreated iPhone screen" : undefined} />
);

export const Title: React.FC<{ kicker?: string; title: string; top?: number }> = ({ kicker, title, top = 90 }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = rise(f, fps);
  return (
    <div style={{ position: "absolute", top, left: 60, right: 60, opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>
      {kicker ? <div style={{ color: C.amber, fontFamily: MONO, fontSize: 28, fontWeight: 700, marginBottom: 10 }}>{kicker}</div> : null}
      <div style={{ color: C.text, fontFamily: FONT, fontSize: 60, fontWeight: 800, lineHeight: 1.08 }}>{title}</div>
    </div>
  );
};

/** iPhone-shaped frame. Children are laid out in a 390 x 844 point screen and scaled to `width`. */
export const Phone: React.FC<{ width: number; x: number; y: number; children: React.ReactNode }> = ({ width, x, y, children }) => {
  const s = width / 390;
  return (
    <div style={{ position: "absolute", left: x, top: y, width: 390 * s + 24, height: 844 * s + 24, borderRadius: 64 * s + 12,
      background: "#1B1E25", padding: 12, boxShadow: "0 30px 80px rgba(0,0,0,0.6)", border: "2px solid #2A2F3A" }}>
      <div style={{ width: 390 * s, height: 844 * s, borderRadius: 54 * s, overflow: "hidden", position: "relative", background: "#000" }}>
        <div style={{ width: 390, height: 844, transform: `scale(${s})`, transformOrigin: "0 0", position: "absolute", fontFamily: FONT, color: C.text }}>
          {children}
          <div style={{ position: "absolute", top: 11, left: 140, width: 110, height: 32, borderRadius: 20, background: "#000" }} />
        </div>
      </div>
    </div>
  );
};

/** Maps a normalised image box onto a cover-fitted image inside a 390 x 844 screen. */
export const coverBox = (iw: number, ih: number, box: [number, number, number, number], sw = 390, sh = 844) => {
  const sc = Math.max(sw / iw, sh / ih);
  const w = iw * sc, h = ih * sc, ox = (sw - w) / 2, oy = (sh - h) / 2;
  return { left: ox + box[0] * w, top: oy + box[1] * h, width: (box[2] - box[0]) * w, height: (box[3] - box[1]) * h };
};

export const SinkPhoto: React.FC = () => (
  <Img src={staticFile("img/sink.png")} style={{ position: "absolute", inset: 0, width: 390, height: 844, objectFit: "cover" }} />
);
export const PovVideo: React.FC = () => (
  <Video src={staticFile("pov/sink.mp4")} loop muted objectFit="cover" style={{ position: "absolute", inset: 0, width: 390, height: 844 }} />
);

/** Outline drawn on the part, with a label chip. */
export const Outline: React.FC<{ rect: ReturnType<typeof coverBox>; label: string; progress: number; color?: string; dashed?: boolean }> = ({ rect, label, progress, color = C.amber, dashed }) => (
  <div style={{ position: "absolute", ...rect, opacity: progress, transform: `scale(${0.85 + 0.15 * progress})` }}>
    <div style={{ position: "absolute", inset: 0, border: `3px ${dashed ? "dashed" : "solid"} ${color}`, borderRadius: 8,
      background: `${color}33`, boxShadow: `0 0 18px ${color}` }} />
    <div style={{ position: "absolute", bottom: "100%", left: -2, marginBottom: 6, padding: "3px 8px", borderRadius: 6,
      background: color, color: "#111", fontSize: 13, fontWeight: 800, whiteSpace: "nowrap" }}>{label}</div>
  </div>
);

export const StatusBar: React.FC<{ title: string; chip?: string; chipColor?: string }> = ({ title, chip, chipColor = C.teal }) => (
  <div style={{ position: "absolute", top: 54, left: 16, right: 16, display: "flex", alignItems: "center", gap: 8 }}>
    <div style={{ padding: "7px 12px", borderRadius: 999, background: "rgba(0,0,0,0.55)", fontSize: 15, fontWeight: 800 }}>{title}</div>
    <div style={{ flex: 1 }} />
    {chip ? <div style={{ padding: "6px 10px", borderRadius: 999, background: "rgba(0,0,0,0.55)", border: `1.5px solid ${chipColor}`, color: chipColor, fontSize: 12, fontWeight: 700 }}>{chip}</div> : null}
  </div>
);

/** Bottom sheet in the Lens UI. */
export const Sheet: React.FC<{ children: React.ReactNode; height: number; progress?: number }> = ({ children, height, progress = 1 }) => (
  <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height, transform: `translateY(${(1 - progress) * height}px)`,
    background: "rgba(14,16,22,0.96)", borderTopLeftRadius: 28, borderTopRightRadius: 28, padding: "14px 20px", borderTop: `1px solid ${C.line}` }}>
    <div style={{ width: 40, height: 5, borderRadius: 3, background: "rgba(255,255,255,0.25)", margin: "0 auto 12px" }} />
    {children}
  </div>
);

/** Concept-clip slot: plays the generated clip if present, else a clearly marked placeholder. */
export const ConceptSlot: React.FC<{ file: string; ready: boolean; from: number; to: number; brief: string; caption: string }> = ({ file, ready, from, to, brief, caption }) => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: C.night }}>
      {ready ? (
        <Video src={staticFile(file)} muted objectFit="cover" style={{ width: "100%", height: "100%" }} />
      ) : (
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
          <div style={{ width: 860, height: 1160, borderRadius: 40, border: `4px dashed ${C.amber}`, display: "flex", flexDirection: "column",
            alignItems: "center", justifyContent: "center", gap: 28, padding: 60, textAlign: "center", opacity: fadeIn(f) }}>
            <div style={{ fontFamily: MONO, color: C.amber, fontSize: 34, fontWeight: 800 }}>CONCEPT CLIP SLOT</div>
            <div style={{ fontFamily: FONT, color: C.text, fontSize: 44, fontWeight: 700, lineHeight: 1.2 }}>{caption}</div>
            <div style={{ fontFamily: FONT, color: C.dim, fontSize: 30, lineHeight: 1.35 }}>{brief}</div>
            <div style={{ fontFamily: MONO, color: C.sky, fontSize: 28 }}>public/{file}</div>
            <div style={{ fontFamily: MONO, color: C.dim, fontSize: 26 }}>frames {from}–{to} · 1080×1920 · {((to - from + 1) / 30).toFixed(0)} s</div>
          </div>
        </AbsoluteFill>
      )}
      {ready ? <CornerTag text="Glasses mode, simulated device" /> : <CornerTag text="Concept, simulated glasses feed" sub="Clip slot" />}
    </AbsoluteFill>
  );
};

/** Caption track rendered from the Caption[] list (no voiceover). */
export const CaptionTrack: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const ms = (f / fps) * 1000;
  const cap = CAPTIONS.find((c) => ms >= c.startMs && ms < c.endMs);
  if (!cap) return null;
  const local = ((ms - cap.startMs) / 1000) * fps;
  const out = ((cap.endMs - ms) / 1000) * fps;
  const o = Math.min(fadeIn(local, 0, 8), interpolate(out, [0, 6], [0, 1], { extrapolateRight: "clamp" }));
  return (
    <div style={{ position: "absolute", left: 60, right: 60, bottom: 90, display: "flex", justifyContent: "center", opacity: o }}>
      <div style={{ padding: "18px 30px", borderRadius: 18, background: "rgba(0,0,0,0.78)", color: C.text, fontFamily: FONT,
        fontSize: 40, fontWeight: 700, lineHeight: 1.25, textAlign: "center", maxWidth: 960 }}>{cap.text}</div>
    </div>
  );
};
