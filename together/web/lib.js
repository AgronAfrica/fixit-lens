// Pure helpers (also unit-tested in relay/test).
export const KIND = { JPEG: 0x01, WAV: 0x02 };
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function normalizeCode(raw) {
  const c = String(raw || "").toUpperCase().replace(/[\s_-]/g, "");
  return c.length >= 4 && c.length <= 8 && [...c].every((ch) => ALPHABET.includes(ch)) ? c : null;
}

export function mediaFrame(kind, seq, payload) {
  const out = new Uint8Array(5 + payload.length);
  out[0] = kind;
  new DataView(out.buffer).setUint32(1, seq >>> 0, false);
  out.set(payload, 5);
  return out;
}

export function parseMedia(bytes) {
  if (!bytes || bytes.length < 5) return null;
  const seq = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(1, false);
  return { kind: bytes[0], seq, payload: bytes.subarray(5) };
}

/** Float32 chunks at `inRate` -> 16-bit mono WAV at `outRate` (linear resample). */
export function encodeWav(chunks, inRate, outRate = 16000) {
  const total = chunks.reduce((n, c) => n + c.length, 0);
  const input = new Float32Array(total);
  let o = 0;
  for (const c of chunks) { input.set(c, o); o += c.length; }
  const ratio = inRate / outRate;
  const n = Math.floor(total / ratio);
  const pcm = new Int16Array(n);
  for (let i = 0; i < n; i++) {
    const p = i * ratio, i0 = Math.floor(p), f = p - i0;
    const s = (input[i0] || 0) * (1 - f) + (input[i0 + 1] || 0) * f;
    pcm[i] = Math.max(-1, Math.min(1, s)) * 0x7fff;
  }
  const buf = new ArrayBuffer(44 + pcm.byteLength);
  const v = new DataView(buf);
  const w = (off, str) => [...str].forEach((ch, i) => v.setUint8(off + i, ch.charCodeAt(0)));
  w(0, "RIFF"); v.setUint32(4, 36 + pcm.byteLength, true); w(8, "WAVE"); w(12, "fmt ");
  v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
  v.setUint32(24, outRate, true); v.setUint32(28, outRate * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true);
  w(36, "data"); v.setUint32(40, pcm.byteLength, true);
  new Int16Array(buf, 44).set(pcm);
  return new Uint8Array(buf);
}

/** Letterbox an iw x ih image into a cw x ch canvas. */
export function containRect(iw, ih, cw, ch) {
  const s = Math.min(cw / iw, ch / ih);
  const w = iw * s, h = ih * s;
  return { x: (cw - w) / 2, y: (ch - h) / 2, w, h };
}

const VOICES = { english: "en-US", hindi: "hi-IN", bengali: "bn-IN", tamil: "ta-IN", telugu: "te-IN", marathi: "mr-IN", kannada: "kn-IN", spanish: "es-ES", french: "fr-FR", portuguese: "pt-BR", indonesian: "id-ID" };
export function voiceCode(lang) {
  return VOICES[String(lang).toLowerCase()] || "en-US";
}
