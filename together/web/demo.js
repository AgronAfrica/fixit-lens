// Two-device demo mode (?demo=1): a SCRIPTED Fixer so the web Helper can be shown without a phone.
// The photo is a real sample image; the outline boxes, captions and memory below are scripted and the
// page says so ("Demo mode · scripted session"). In a real session they come from SAM 3.1, Muse Voice
// Transcribe and Muse Spark running on the Fixer's phone.
const REGIONS = [
  // Hand-placed boxes from the app's DemoLibrary (normalised x0, y0, x1, y1).
  { label: "slip nut", box: [0.52, 0.42, 0.64, 0.49] },
  { label: "upper slip nut", box: [0.52, 0.30, 0.64, 0.36] },
  { label: "leaking pipe joint", box: [0.43, 0.34, 0.65, 0.49] },
  { label: "tailpiece", box: [0.50, 0.20, 0.66, 0.30] },
  { label: "waste arm", box: [0.0, 0.35, 0.46, 0.41] },
  { label: "bucket", box: [0.35, 0.58, 0.86, 0.91] },
];

const REPLIES = [
  { original: "Ya veo la tuerca. ¿La giro a la derecha?", translated: "I can see the nut. Do I turn it to the right?" },
  { original: "Listo, ya no gotea.", translated: "Done, it's not dripping any more." },
];

const HELPER_LINES = [
  { original: "Turn the slip nut clockwise, hand tight, then a quarter more.", translated: "Gira la tuerca en el sentido del reloj, a mano, y luego un cuarto más." },
  { original: "Great. Run the tap for a minute and check for drips.", translated: "Genial. Abre el grifo un minuto y revisa si gotea." },
];

// ?demo=1&pov=1 uses the same recorded point-of-view clip the iOS app feeds into the DAT Mock Device
// ("simulated glasses feed"), so the Helper sees what a glasses-wearing Fixer would stream.
export function runDemo({ onFrame, onMessage, setLink, lang, name, pov = false }) {
  let seq = 0;
  const t0 = performance.now();
  let replies = 0;
  let spoken = 0;
  const img = new Image();
  img.src = "demo-sink.jpg";
  const c = document.createElement("canvas");
  c.width = 504; c.height = 896; // DAT glasses "medium" stream size, portrait
  const g = c.getContext("2d");

  setLink("live", pov ? "Live · demo · simulated glasses feed" : "Live · demo");
  if (Array.isArray(window.FIXIT_POV_FRAMES) && pov) {
    // Recording harness only (scripts/record_helper.sh): the same POV clip as decoded JPEG frames, 12 fps.
    const frames = window.FIXIT_POV_FRAMES.map((src) => Object.assign(new Image(), { src }));
    setInterval(() => {
      const f = frames[Math.floor(((performance.now() - t0) / 1000) * 12) % frames.length];
      if (!f.complete) return;
      g.drawImage(f, 0, 0, c.width, c.height);
      c.toBlob(async (b) => onFrame(new Uint8Array(await b.arrayBuffer()), ++seq), "image/jpeg", 0.75);
    }, 1000 / 12);
  } else if (pov) {
    const v = document.createElement("video");
    Object.assign(v, { src: "demo-pov-sink.mp4", muted: true, loop: true, playsInline: true, autoplay: true });
    v.addEventListener("loadeddata", () => {
      v.play();
      setInterval(() => {
        g.drawImage(v, 0, 0, c.width, c.height);
        c.toBlob(async (b) => onFrame(new Uint8Array(await b.arrayBuffer()), ++seq), "image/jpeg", 0.75);
      }, 1000 / 12);
    }, { once: true });
  } else img.onload = () => {
    const frame = () => {
      // Gentle handheld drift so the frame visibly updates like a live stream.
      const t = (performance.now() - t0) / 1000;
      const s = Math.max(c.width / img.width, c.height / img.height) * 1.06;
      const dx = Math.sin(t * 0.7) * 6, dy = Math.cos(t * 0.5) * 5;
      g.drawImage(img, (c.width - img.width * s) / 2 + dx, (c.height - img.height * s) / 2 + dy, img.width * s, img.height * s);
      c.toBlob(async (b) => onFrame(new Uint8Array(await b.arrayBuffer()), ++seq), "image/jpeg", 0.75);
    };
    frame();
    setInterval(frame, 1000 / 12);
  };
  setTimeout(() => onMessage({ t: "peers", count: 2, helpers: [name], fixer: true }), 800);
  setTimeout(() => onMessage({ t: "caption", caption: { id: "d1", from: "fixer", name: "Ana (Fixer)", original: "Hay agua goteando debajo del fregadero.", originalLanguage: "spanish", translated: "There's water dripping under the sink.", translatedLanguage: lang } }), 1600);

  return {
    receive(msg) {
      if (msg.t === "tap") {
        const hit = REGIONS.find((r) => msg.x >= r.box[0] && msg.x <= r.box[2] && msg.y >= r.box[1] && msg.y <= r.box[3])
          || { label: "part", box: [Math.max(0, msg.x - 0.07), Math.max(0, msg.y - 0.05), Math.min(1, msg.x + 0.07), Math.min(1, msg.y + 0.05)] };
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
          "Run the tap for a minute and check for drips.",
        ] }), 2200);
      }
    },
  };
}
