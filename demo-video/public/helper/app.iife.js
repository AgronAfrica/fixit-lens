(() => {
  // ../../samdevna/META HACKATON/samdevna/together/web/lib.js
  var KIND = { JPEG: 1, WAV: 2 };
  var ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  function normalizeCode(raw) {
    const c = String(raw || "").toUpperCase().replace(/[\s_-]/g, "");
    return c.length >= 4 && c.length <= 8 && [...c].every((ch) => ALPHABET.includes(ch)) ? c : null;
  }
  function mediaFrame(kind, seq, payload) {
    const out = new Uint8Array(5 + payload.length);
    out[0] = kind;
    new DataView(out.buffer).setUint32(1, seq >>> 0, false);
    out.set(payload, 5);
    return out;
  }
  function parseMedia(bytes) {
    if (!bytes || bytes.length < 5) return null;
    const seq = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(1, false);
    return { kind: bytes[0], seq, payload: bytes.subarray(5) };
  }
  function encodeWav(chunks, inRate, outRate = 16e3) {
    const total = chunks.reduce((n2, c) => n2 + c.length, 0);
    const input = new Float32Array(total);
    let o = 0;
    for (const c of chunks) {
      input.set(c, o);
      o += c.length;
    }
    const ratio = inRate / outRate;
    const n = Math.floor(total / ratio);
    const pcm = new Int16Array(n);
    for (let i = 0; i < n; i++) {
      const p = i * ratio, i0 = Math.floor(p), f = p - i0;
      const s = (input[i0] || 0) * (1 - f) + (input[i0 + 1] || 0) * f;
      pcm[i] = Math.max(-1, Math.min(1, s)) * 32767;
    }
    const buf = new ArrayBuffer(44 + pcm.byteLength);
    const v = new DataView(buf);
    const w = (off, str) => [...str].forEach((ch, i) => v.setUint8(off + i, ch.charCodeAt(0)));
    w(0, "RIFF");
    v.setUint32(4, 36 + pcm.byteLength, true);
    w(8, "WAVE");
    w(12, "fmt ");
    v.setUint32(16, 16, true);
    v.setUint16(20, 1, true);
    v.setUint16(22, 1, true);
    v.setUint32(24, outRate, true);
    v.setUint32(28, outRate * 2, true);
    v.setUint16(32, 2, true);
    v.setUint16(34, 16, true);
    w(36, "data");
    v.setUint32(40, pcm.byteLength, true);
    new Int16Array(buf, 44).set(pcm);
    return new Uint8Array(buf);
  }
  function containRect(iw, ih, cw, ch) {
    const s = Math.min(cw / iw, ch / ih);
    const w = iw * s, h = ih * s;
    return { x: (cw - w) / 2, y: (ch - h) / 2, w, h };
  }
  var VOICES = { english: "en-US", hindi: "hi-IN", bengali: "bn-IN", tamil: "ta-IN", telugu: "te-IN", marathi: "mr-IN", kannada: "kn-IN", spanish: "es-ES", french: "fr-FR", portuguese: "pt-BR", indonesian: "id-ID" };
  function voiceCode(lang) {
    return VOICES[String(lang).toLowerCase()] || "en-US";
  }

  // ../../samdevna/META HACKATON/samdevna/together/web/demo.js
  var REGIONS = [
    // Hand-placed boxes from the app's DemoLibrary (normalised x0, y0, x1, y1).
    { label: "slip nut", box: [0.52, 0.42, 0.64, 0.49] },
    { label: "upper slip nut", box: [0.52, 0.3, 0.64, 0.36] },
    { label: "leaking pipe joint", box: [0.43, 0.34, 0.65, 0.49] },
    { label: "tailpiece", box: [0.5, 0.2, 0.66, 0.3] },
    { label: "waste arm", box: [0, 0.35, 0.46, 0.41] },
    { label: "bucket", box: [0.35, 0.58, 0.86, 0.91] }
  ];
  var REPLIES = [
    { original: "Ya veo la tuerca. \xBFLa giro a la derecha?", translated: "I can see the nut. Do I turn it to the right?" },
    { original: "Listo, ya no gotea.", translated: "Done, it's not dripping any more." }
  ];
  var HELPER_LINES = [
    { original: "Turn the slip nut clockwise, hand tight, then a quarter more.", translated: "Gira la tuerca en el sentido del reloj, a mano, y luego un cuarto m\xE1s." },
    { original: "Great. Run the tap for a minute and check for drips.", translated: "Genial. Abre el grifo un minuto y revisa si gotea." }
  ];
  function runDemo({ onFrame, onMessage, setLink: setLink2, lang, name, pov = false }) {
    let seq = 0;
    const t0 = performance.now();
    let replies = 0;
    let spoken = 0;
    const img = new Image();
    img.src = "demo-sink.jpg";
    const c = document.createElement("canvas");
    c.width = 504;
    c.height = 896;
    const g = c.getContext("2d");
    setLink2("live", pov ? "Live \xB7 demo \xB7 simulated glasses feed" : "Live \xB7 demo");
    if (Array.isArray(window.FIXIT_POV_FRAMES) && pov) {
      const frames = window.FIXIT_POV_FRAMES.map((src) => Object.assign(new Image(), { src }));
      setInterval(() => {
        const f = frames[Math.floor((performance.now() - t0) / 1e3 * 12) % frames.length];
        if (!f.complete) return;
        g.drawImage(f, 0, 0, c.width, c.height);
        c.toBlob(async (b) => onFrame(new Uint8Array(await b.arrayBuffer()), ++seq), "image/jpeg", 0.75);
      }, 1e3 / 12);
    } else if (pov) {
      const v = document.createElement("video");
      Object.assign(v, { src: "demo-pov-sink.mp4", muted: true, loop: true, playsInline: true, autoplay: true });
      v.addEventListener("loadeddata", () => {
        v.play();
        setInterval(() => {
          g.drawImage(v, 0, 0, c.width, c.height);
          c.toBlob(async (b) => onFrame(new Uint8Array(await b.arrayBuffer()), ++seq), "image/jpeg", 0.75);
        }, 1e3 / 12);
      }, { once: true });
    } else img.onload = () => {
      const frame = () => {
        const t = (performance.now() - t0) / 1e3;
        const s = Math.max(c.width / img.width, c.height / img.height) * 1.06;
        const dx = Math.sin(t * 0.7) * 6, dy = Math.cos(t * 0.5) * 5;
        g.drawImage(img, (c.width - img.width * s) / 2 + dx, (c.height - img.height * s) / 2 + dy, img.width * s, img.height * s);
        c.toBlob(async (b) => onFrame(new Uint8Array(await b.arrayBuffer()), ++seq), "image/jpeg", 0.75);
      };
      frame();
      setInterval(frame, 1e3 / 12);
    };
    setTimeout(() => onMessage({ t: "peers", count: 2, helpers: [name], fixer: true }), 800);
    setTimeout(() => onMessage({ t: "caption", caption: { id: "d1", from: "fixer", name: "Ana (Fixer)", original: "Hay agua goteando debajo del fregadero.", originalLanguage: "spanish", translated: "There's water dripping under the sink.", translatedLanguage: lang } }), 1600);
    return {
      receive(msg) {
        if (msg.t === "tap") {
          const hit = REGIONS.find((r) => msg.x >= r.box[0] && msg.x <= r.box[2] && msg.y >= r.box[1] && msg.y <= r.box[3]) || { label: "part", box: [Math.max(0, msg.x - 0.07), Math.max(0, msg.y - 0.05), Math.min(1, msg.x + 0.07), Math.min(1, msg.y + 0.05)] };
          const mask = { id: `m${seq}`, seq, box: hit.box, png: "", label: hit.label, confidence: 0, by: name, model: "demo (scripted box)" };
          setTimeout(() => onMessage({ t: "mask", mask }), 450);
          setTimeout(() => {
            if (replies >= REPLIES.length) return;
            const r = REPLIES[replies++];
            onMessage({ t: "caption", caption: { id: `r${replies}`, from: "fixer", name: "Ana (Fixer)", original: r.original, originalLanguage: "spanish", translated: r.translated, translatedLanguage: lang } });
          }, 2600);
        } else if (msg.t === "clear_mask") {
          onMessage({ t: "clear_mask" });
        }
      },
      receiveAudio() {
        const l = HELPER_LINES[Math.min(spoken++, HELPER_LINES.length - 1)];
        setTimeout(() => onMessage({ t: "caption", caption: { id: `h${spoken}`, from: "helper", name, original: l.original, originalLanguage: lang, translated: l.translated, translatedLanguage: "spanish" } }), 700);
        if (spoken === 2) {
          setTimeout(() => onMessage({ t: "memory", title: "Fix a dripping sink trap", steps: [
            "Put a bucket under the trap.",
            "Find the leaking slip nut on the trap.",
            "Turn it clockwise by hand, then a quarter turn more.",
            "Run the tap for a minute and check for drips."
          ] }), 2200);
        }
      }
    };
  }

  // ../../samdevna/META HACKATON/samdevna/together/web/app.js
  var $ = (id) => document.getElementById(id);
  var params = new URLSearchParams(location.search);
  var RELAY = (params.get("relay") || window.FIXIT_RELAY || location.origin).replace(/\/$/, "");
  var pid = Math.random().toString(36).slice(2, 10);
  var state = {
    code: "",
    name: "",
    lang: "english",
    ws: null,
    mode: "connecting",
    seq: 0,
    frames: 0,
    fpsAt: performance.now(),
    fps: 0,
    image: null,
    mask: null,
    maskImg: null,
    ripple: null,
    voice: true,
    pollAfter: 0,
    pollTimer: null,
    retries: 0,
    demo: null,
    recording: null
  };
  var pathCode = location.pathname.match(/\/j\/([A-Za-z0-9-]+)/)?.[1] || params.get("code");
  if (pathCode) $("code").value = normalizeCode(pathCode) || pathCode;
  $("name").value = localStorage.getItem("fixit.name") || "";
  $("lang").value = localStorage.getItem("fixit.lang") || ((navigator.language || "en").startsWith("es") ? "spanish" : "english");
  $("joinForm").addEventListener("submit", (e) => {
    e.preventDefault();
    const code = normalizeCode($("code").value);
    if (!code) {
      $("code").setCustomValidity("Codes are 4\u20138 letters and numbers");
      $("code").reportValidity();
      return;
    }
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
      if (pov) $("demoTag").textContent = "Demo mode \xB7 scripted session \xB7 simulated glasses feed";
      state.demo = runDemo({ onFrame: showFrame, onMessage: handle, setLink, lang: state.lang, name: state.name, pov });
    } else {
      connect();
    }
  }
  function connect() {
    setLink("connecting", "Connecting\u2026");
    const url = `${RELAY.replace(/^http/, "ws")}/ws/${state.code}?role=helper&name=${encodeURIComponent(state.name)}&lang=${state.lang}`;
    let opened = false;
    let ws;
    try {
      ws = new WebSocket(url);
    } catch {
      return startPolling();
    }
    ws.binaryType = "arraybuffer";
    state.ws = ws;
    const giveUp = setTimeout(() => {
      if (!opened) {
        try {
          ws.close();
        } catch {
        }
        startPolling();
      }
    }, 6e3);
    ws.onopen = () => {
      opened = true;
      clearTimeout(giveUp);
      state.retries = 0;
      stopPolling();
      setLink("live", "Live");
      send({ t: "hello", role: "helper", name: state.name, lang: state.lang, platform: "web" });
    };
    ws.onmessage = (e) => {
      if (typeof e.data === "string") {
        try {
          handle(JSON.parse(e.data));
        } catch {
        }
        return;
      }
      const media = parseMedia(new Uint8Array(e.data));
      if (media?.kind === KIND.JPEG) showFrame(media.payload, media.seq);
    };
    ws.onclose = (e) => {
      clearTimeout(giveUp);
      state.ws = null;
      if (e.code === 4429) return setLink("down", "Room full (max 4)");
      startPolling();
      const wait = Math.min(15e3, 1e3 * 2 ** state.retries++);
      setTimeout(() => {
        if (!state.ws) connect();
      }, wait);
    };
  }
  function startPolling() {
    if (state.pollTimer || state.demo) return;
    setLink("snapshot", "Snapshot mode \xB7 1 frame/s");
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
        setLink("down", "Offline \xB7 retrying");
      }
    };
    tick();
    state.pollTimer = setInterval(tick, 1e3);
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
    fetch(`${RELAY}/api/rooms/${state.code}/messages?role=helper&pid=${pid}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(msg) }).catch(() => {
    });
  }
  function sendAudio(bytes) {
    if (state.demo) return state.demo.receiveAudio(bytes);
    if (state.ws?.readyState === 1) state.ws.send(bytes);
    else fetch(`${RELAY}/api/rooms/${state.code}/audio?pid=${pid}`, { method: "POST", body: bytes }).catch(() => {
    });
  }
  function setLink(kind, text) {
    state.mode = kind;
    $("linkPill").className = `pill ${kind}`;
    $("linkText").textContent = text;
  }
  function handle(msg) {
    switch (msg.t) {
      case "peers":
        $("peerText").textContent = msg.fixer === false ? "Waiting for Fixer" : `${msg.count} in session`;
        break;
      case "status":
        addSystem(msg.text);
        break;
      case "mask":
        setMask(msg.mask);
        break;
      case "clear_mask":
        state.mask = null;
        state.maskImg = null;
        $("maskTag").classList.remove("on");
        draw();
        break;
      case "caption":
        addCaption(msg.caption);
        break;
      case "memory":
        showMemory(msg.title, msg.steps);
        break;
      case "safety":
        showSafety(msg.reason);
        break;
      case "mode":
        if (state.mode === "live" && msg.mode === "snapshot") setLink("snapshot", "Snapshot mode \xB7 weak link");
        else if (msg.mode === "live" && state.ws) setLink("live", "Live");
        break;
    }
  }
  var canvas = $("view");
  var ctx = canvas.getContext("2d");
  function resize() {
    const r = canvas.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.max(1, Math.round(r.width * dpr));
    canvas.height = Math.max(1, Math.round(r.height * dpr));
    draw();
  }
  addEventListener("resize", resize);
  if ("ResizeObserver" in window) new ResizeObserver(() => resize()).observe($("stage"));
  async function showFrame(jpeg, seq) {
    try {
      const bitmap = await createImageBitmap(new Blob([jpeg], { type: "image/jpeg" }));
      state.image?.close?.();
      state.image = bitmap;
      state.seq = seq;
      state.frames++;
      const now = performance.now();
      if (now - state.fpsAt > 1e3) {
        state.fps = Math.round(state.frames * 1e3 / (now - state.fpsAt));
        state.frames = 0;
        state.fpsAt = now;
        if (state.mode === "live") $("linkText").textContent = `Live \xB7 ${state.fps} fps`;
      }
      draw();
      if (state.ws?.readyState === 1) state.ws.send(JSON.stringify({ t: "ack", seq }));
    } catch {
    }
  }
  async function setMask(mask) {
    state.mask = mask;
    state.maskImg = null;
    if (mask.png) {
      const img = new Image();
      img.onload = () => {
        state.maskImg = img;
        draw();
      };
      img.src = `data:image/png;base64,${mask.png}`;
    }
    $("maskTag").textContent = `${mask.model || "sam-3.1"} \xB7 ${mask.label || "part"}${mask.confidence ? ` \xB7 ${Math.round(mask.confidence * 100)}%` : ""}`;
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
      ctx.fillText("Waiting for the Fixer's camera\u2026", canvas.width / 2, canvas.height / 2);
      return;
    }
    const f = frameRect();
    ctx.drawImage(state.image, f.x, f.y, f.w, f.h);
    if (state.mask) {
      const [x0, y0, x1, y1] = state.mask.box;
      const bx = f.x + x0 * f.w, by = f.y + y0 * f.h, bw = (x1 - x0) * f.w, bh = (y1 - y0) * f.h;
      if (state.maskImg) {
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
    $("hint").textContent = "SAM 3.1 is outlining it on their phone\u2026";
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
  function addCaption(c) {
    const mine = c.from === "helper" && c.name === state.name;
    const el = document.createElement("div");
    el.className = `cap${mine ? " me" : ""}`;
    const shown = mine ? c.original : c.translated || c.original;
    const other = mine ? c.translated && c.translated !== c.original ? c.translated : "" : c.translated && c.translated !== c.original ? c.original : "";
    el.innerHTML = `<div class="who">${escapeHtml(mine ? "You" : c.name || "Fixer")}<i>muse-voice-transcribe${c.translated && c.translated !== c.original ? " \u2192 muse-spark" : ""}</i></div><div class="tr"></div>${other ? '<div class="orig"></div>' : ""}`;
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
  var mic = $("micBtn");
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
      mic.querySelector("span").textContent = "Listening\u2026";
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
    const seconds = (performance.now() - rec.started) / 1e3;
    const rate = rec.ac.sampleRate;
    rec.ac.close();
    if (seconds < 0.4) return;
    const wav = encodeWav(rec.chunks, rate, 16e3);
    sendAudio(mediaFrame(KIND.WAV, Date.now() >>> 0, wav));
    addSystem("Sent. Muse Voice Transcribe is hearing you on their phone\u2026");
  }
  if (params.get("demo") === "1") start("DEMO42", true);
})();
