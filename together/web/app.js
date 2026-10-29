// Fix it together: web Helper. Thin client: shows the Fixer's live camera, sends taps and voice clips.
// SAM 3.1, Muse Voice Transcribe and Muse Spark run on the Fixer's phone; this page holds no keys.
import { encodeWav, mediaFrame, parseMedia, normalizeCode, voiceCode, containRect, KIND } from "./lib.js";
import { runDemo } from "./demo.js";

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const RELAY = (params.get("relay") || window.FIXIT_RELAY || location.origin).replace(/\/$/, "");
const pid = Math.random().toString(36).slice(2, 10);

const state = {
  code: "", name: "", lang: "english",
  ws: null, mode: "connecting", seq: 0, frames: 0, fpsAt: performance.now(), fps: 0,
  image: null, mask: null, maskImg: null, ripple: null, voice: true, pollAfter: 0, pollTimer: null,
  retries: 0, demo: null, recording: null,
};

// ---------- join

const pathCode = location.pathname.match(/\/j\/([A-Za-z0-9-]+)/)?.[1] || params.get("code");
if (pathCode) $("code").value = normalizeCode(pathCode) || pathCode;
$("name").value = localStorage.getItem("fixit.name") || "";
$("lang").value = localStorage.getItem("fixit.lang") || ((navigator.language || "en").startsWith("es") ? "spanish" : "english");

$("joinForm").addEventListener("submit", (e) => {
  e.preventDefault();
  const code = normalizeCode($("code").value);
  if (!code) { $("code").setCustomValidity("Codes are 4–8 letters and numbers"); $("code").reportValidity(); return; }
  start(code, false);
});
$("code").addEventListener("input", () => $("code").setCustomValidity(""));
$("demoBtn").addEventListener("click", () => start("DEMO42", true));

function start(code, demo) {
  state.code = code;
  state.name = $("name").value.trim() || "Helper";
  state.lang = $("lang").value;
  localStorage.setItem("fixit.name", state.name);
  localStorage.setItem("fixit.lang", state.lang);
  $("join").classList.add("hidden");
  $("live").classList.remove("hidden");
  resize();
  if (demo) {
    $("demoTag").classList.remove("hidden");
    const pov = new URLSearchParams(location.search).has("pov");
    if (pov) $("demoTag").textContent = "Demo mode · scripted session · simulated glasses feed";
    state.demo = runDemo({ onFrame: showFrame, onMessage: handle, setLink, lang: state.lang, name: state.name, pov });
  } else {
    connect();
  }
}

// ---------- transport: WebSocket live mode, HTTP snapshot fallback

function connect() {
  setLink("connecting", "Connecting…");
  const url = `${RELAY.replace(/^http/, "ws")}/ws/${state.code}?role=helper&name=${encodeURIComponent(state.name)}&lang=${state.lang}`;
  let opened = false;
  let ws;
  try { ws = new WebSocket(url); } catch { return startPolling(); }
  ws.binaryType = "arraybuffer";
  state.ws = ws;
  const giveUp = setTimeout(() => { if (!opened) { try { ws.close(); } catch {} startPolling(); } }, 6000);
  ws.onopen = () => {
    opened = true;
    clearTimeout(giveUp);
    state.retries = 0;
    stopPolling();
    setLink("live", "Live");
    send({ t: "hello", role: "helper", name: state.name, lang: state.lang, platform: "web" });
  };
  ws.onmessage = (e) => {
    if (typeof e.data === "string") { try { handle(JSON.parse(e.data)); } catch {} return; }
    const media = parseMedia(new Uint8Array(e.data));
    if (media?.kind === KIND.JPEG) showFrame(media.payload, media.seq);
  };
  ws.onclose = (e) => {
    clearTimeout(giveUp);
    state.ws = null;
    if (e.code === 4429) return setLink("down", "Room full (max 4)");
    // Stream dropped: keep helping in snapshot mode while we retry the socket.
    startPolling();
    const wait = Math.min(15000, 1000 * 2 ** state.retries++);
    setTimeout(() => { if (!state.ws) connect(); }, wait);
  };
}

function startPolling() {
  if (state.pollTimer || state.demo) return;
  setLink("snapshot", "Snapshot mode · 1 frame/s");
  postMessage({ t: "hello", role: "helper", name: state.name, lang: state.lang, platform: "web" });
  const tick = async () => {
    try {
      const r = await fetch(`${RELAY}/api/rooms/${state.code}/snapshot?pid=${pid}`, { cache: "no-store" });
      if (r.status === 200) showFrame(new Uint8Array(await r.arrayBuffer()), Number(r.headers.get("X-Seq") || 0));
      const m = await (await fetch(`${RELAY}/api/rooms/${state.code}/messages?role=helper&after=${state.pollAfter}&pid=${pid}`, { cache: "no-store" })).json();
      state.pollAfter = m.last ?? state.pollAfter;
      for (const msg of m.messages || []) handle(msg);
      if (m.peers) handle({ t: "peers", ...m.peers });
    } catch {
      setLink("down", "Offline · retrying");
    }
  };
  tick();
  state.pollTimer = setInterval(tick, 1000);
}

function stopPolling() {
  clearInterval(state.pollTimer);
  state.pollTimer = null;
}

function send(msg) {
  if (state.demo) return state.demo.receive(msg);
  if (state.ws?.readyState === 1) state.ws.send(JSON.stringify(msg));
  else postMessage(msg);
}

function postMessage(msg) {
  fetch(`${RELAY}/api/rooms/${state.code}/messages?role=helper&pid=${pid}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(msg) }).catch(() => {});
}

function sendAudio(bytes) {
  if (state.demo) return state.demo.receiveAudio(bytes);
  if (state.ws?.readyState === 1) state.ws.send(bytes);
  else fetch(`${RELAY}/api/rooms/${state.code}/audio?pid=${pid}`, { method: "POST", body: bytes }).catch(() => {});
}

function setLink(kind, text) {
  state.mode = kind;
  $("linkPill").className = `pill ${kind}`;
  $("linkText").textContent = text;
}

// ---------- messages from the Fixer

function handle(msg) {
  switch (msg.t) {
    case "peers": $("peerText").textContent = msg.fixer === false ? "Waiting for Fixer" : `${msg.count} in session`; break;
    case "status": addSystem(msg.text); break;
    case "mask": setMask(msg.mask); break;
    case "clear_mask": state.mask = null; state.maskImg = null; $("maskTag").classList.remove("on"); draw(); break;
    case "caption": addCaption(msg.caption); break;
    case "memory": showMemory(msg.title, msg.steps); break;
    case "safety": showSafety(msg.reason); break;
    case "mode": if (state.mode === "live" && msg.mode === "snapshot") setLink("snapshot", "Snapshot mode · weak link"); else if (msg.mode === "live" && state.ws) setLink("live", "Live"); break;
  }
}

// ---------- drawing

const canvas = $("view");
const ctx = canvas.getContext("2d");

function resize() {
  const r = canvas.getBoundingClientRect();
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.max(1, Math.round(r.width * dpr));
  canvas.height = Math.max(1, Math.round(r.height * dpr));
  draw();
}
addEventListener("resize", resize);
// The stage shrinks as captions and the memory card appear: keep the canvas matched so taps map correctly.
if ("ResizeObserver" in window) new ResizeObserver(() => resize()).observe($("stage"));

async function showFrame(jpeg, seq) {
  try {
    const bitmap = await createImageBitmap(new Blob([jpeg], { type: "image/jpeg" }));
    state.image?.close?.();
    state.image = bitmap;
    state.seq = seq;
    state.frames++;
    const now = performance.now();
    if (now - state.fpsAt > 1000) {
      state.fps = Math.round((state.frames * 1000) / (now - state.fpsAt));
      state.frames = 0;
      state.fpsAt = now;
      if (state.mode === "live") $("linkText").textContent = `Live · ${state.fps} fps`;
    }
    draw();
    // Ack after drawing: the Fixer only sends more when we keep up, so the picture stays fresh.
    if (state.ws?.readyState === 1) state.ws.send(JSON.stringify({ t: "ack", seq }));
  } catch {}
}

async function setMask(mask) {
  state.mask = mask;
  state.maskImg = null;
  if (mask.png) {
    const img = new Image();
    img.onload = () => { state.maskImg = img; draw(); };
    img.src = `data:image/png;base64,${mask.png}`;
  }
  $("maskTag").textContent = `${mask.model || "sam-3.1"} · ${mask.label || "part"}${mask.confidence ? ` · ${Math.round(mask.confidence * 100)}%` : ""}`;
  $("maskTag").classList.add("on");
  $("hint").textContent = "Outlined on their screen too";
  draw();
}

function frameRect() {
  const iw = state.image?.width || 9, ih = state.image?.height || 16;
  return containRect(iw, ih, canvas.width, canvas.height);
}

function draw() {
  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  if (!state.image) {
    ctx.fillStyle = "#9AA3B2";
    ctx.font = `${16 * (devicePixelRatio || 1)}px system-ui`;
    ctx.textAlign = "center";
    ctx.fillText("Waiting for the Fixer's camera…", canvas.width / 2, canvas.height / 2);
    return;
  }
  const f = frameRect();
  ctx.drawImage(state.image, f.x, f.y, f.w, f.h);
  if (state.mask) {
    const [x0, y0, x1, y1] = state.mask.box;
    const bx = f.x + x0 * f.w, by = f.y + y0 * f.h, bw = (x1 - x0) * f.w, bh = (y1 - y0) * f.h;
    if (state.maskImg) {
      // Tint the white mask amber.
      const off = new OffscreenCanvas(Math.max(1, Math.round(bw)), Math.max(1, Math.round(bh)));
      const o = off.getContext("2d");
      o.drawImage(state.maskImg, 0, 0, off.width, off.height);
      o.globalCompositeOperation = "source-in";
      o.fillStyle = "rgba(255,176,32,0.45)";
      o.fillRect(0, 0, off.width, off.height);
      ctx.drawImage(off, bx, by);
    } else {
      ctx.fillStyle = "rgba(255,176,32,0.18)";
      ctx.fillRect(bx, by, bw, bh);
    }
    ctx.strokeStyle = "#FFB020";
    ctx.lineWidth = 3 * (devicePixelRatio || 1);
    ctx.setLineDash(state.maskImg ? [] : [10, 6]);
    roundRect(bx, by, bw, bh, 10);
    ctx.stroke();
    ctx.setLineDash([]);
  }
  if (state.ripple) {
    const age = (performance.now() - state.ripple.at) / 600;
    if (age < 1) {
      ctx.strokeStyle = `rgba(255,176,32,${1 - age})`;
      ctx.lineWidth = 3 * (devicePixelRatio || 1);
      ctx.beginPath();
      ctx.arc(f.x + state.ripple.x * f.w, f.y + state.ripple.y * f.h, 12 + age * 40, 0, Math.PI * 2);
      ctx.stroke();
      requestAnimationFrame(draw);
    } else state.ripple = null;
  }
}

function roundRect(x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

canvas.addEventListener("pointerdown", (e) => {
  if (!state.image) return;
  const r = canvas.getBoundingClientRect();
  const dpr = canvas.width / r.width;
  const f = frameRect();
  const x = ((e.clientX - r.left) * dpr - f.x) / f.w;
  const y = ((e.clientY - r.top) * dpr - f.y) / f.h;
  if (x < 0 || x > 1 || y < 0 || y > 1) return;
  state.ripple = { x, y, at: performance.now() };
  $("hint").textContent = "SAM 3.1 is outlining it on their phone…";
  send({ t: "tap", seq: state.seq, x: +x.toFixed(4), y: +y.toFixed(4), by: state.name });
  navigator.vibrate?.(10);
  draw();
});

$("clearBtn").addEventListener("click", () => send({ t: "clear_mask" }));
$("leaveBtn").addEventListener("click", () => location.assign(location.pathname.startsWith("/j/") ? "/" : location.pathname));
$("muteBtn").addEventListener("click", () => {
  state.voice = !state.voice;
  $("muteBtn").textContent = state.voice ? "Voice on" : "Voice off";
  if (!state.voice) speechSynthesis.cancel();
});

// ---------- captions (translated on the Fixer's phone by Muse Spark, spoken here by the browser's own TTS)

function addCaption(c) {
  const mine = c.from === "helper" && c.name === state.name;
  const el = document.createElement("div");
  el.className = `cap${mine ? " me" : ""}`;
  const shown = mine ? c.original : (c.translated || c.original);
  const other = mine ? (c.translated && c.translated !== c.original ? c.translated : "") : (c.translated && c.translated !== c.original ? c.original : "");
  el.innerHTML = `<div class="who">${escapeHtml(mine ? "You" : c.name || "Fixer")}<i>muse-voice-transcribe${c.translated && c.translated !== c.original ? " → muse-spark" : ""}</i></div><div class="tr"></div>${other ? '<div class="orig"></div>' : ""}`;
  el.querySelector(".tr").textContent = shown;
  if (other) el.querySelector(".orig").textContent = other;
  $("captions").prepend(el);
  if (!mine && state.voice && "speechSynthesis" in window) {
    const u = new SpeechSynthesisUtterance(shown);
    u.lang = voiceCode(c.translatedLanguage || state.lang);
    speechSynthesis.speak(u);
  }
}

function addSystem(text) {
  const el = document.createElement("div");
  el.className = "cap";
  el.innerHTML = '<div class="who">Session</div><div class="orig"></div>';
  el.querySelector(".orig").textContent = text;
  $("captions").prepend(el);
}

function showMemory(title, steps) {
  $("memory").classList.remove("hidden");
  $("memory").querySelector("h2").firstChild.textContent = `${title || "Repair memory"} `;
  $("memorySteps").replaceChildren(...steps.map((s) => Object.assign(document.createElement("li"), { textContent: s })));
}

function showSafety(reason) {
  $("safety").classList.remove("hidden");
  $("safetyText").textContent = reason;
  speechSynthesis.cancel();
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

// ---------- push to talk: 16 kHz mono WAV, sent to the Fixer's phone for Muse Voice Transcribe

const mic = $("micBtn");
mic.addEventListener("pointerdown", startTalking);
for (const ev of ["pointerup", "pointerleave", "pointercancel"]) mic.addEventListener(ev, stopTalking);

async function startTalking(e) {
  e.preventDefault();
  if (state.recording) return;
  speechSynthesis.cancel();
  if (state.demo) {
    mic.classList.add("rec");
    state.recording = { demo: true };
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } });
    const ac = new AudioContext();
    const src = ac.createMediaStreamSource(stream);
    const proc = ac.createScriptProcessor(4096, 1, 1);
    const chunks = [];
    proc.onaudioprocess = (ev) => chunks.push(new Float32Array(ev.inputBuffer.getChannelData(0)));
    src.connect(proc);
    proc.connect(ac.destination);
    state.recording = { stream, ac, proc, chunks, started: performance.now() };
    mic.classList.add("rec");
    mic.querySelector("span").textContent = "Listening…";
  } catch {
    addSystem("Microphone blocked. Allow it in the browser to talk.");
  }
}

function stopTalking() {
  const rec = state.recording;
  if (!rec) return;
  state.recording = null;
  mic.classList.remove("rec");
  mic.querySelector("span").textContent = "Hold to talk";
  if (rec.demo) return state.demo.receiveAudio(null);
  rec.proc.disconnect();
  rec.stream.getTracks().forEach((t) => t.stop());
  const seconds = (performance.now() - rec.started) / 1000;
  const rate = rec.ac.sampleRate;
  rec.ac.close();
  if (seconds < 0.4) return;
  const wav = encodeWav(rec.chunks, rate, 16000);
  sendAudio(mediaFrame(KIND.WAV, Date.now() >>> 0, wav));
  addSystem("Sent. Muse Voice Transcribe is hearing you on their phone…");
}

// Auto-start the labelled demo last, once everything above (canvas, handlers) exists.
if (params.get("demo") === "1") start("DEMO42", true);
