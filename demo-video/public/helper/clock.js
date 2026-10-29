// Recording harness only: a deterministic clock so each video frame shows the REAL web client exactly
// t seconds into its labelled demo session. Timers, performance.now and rAF run on this clock.
(function () {
  const q = []; let now = 0, idc = 1;
  const realST = window.setTimeout.bind(window);
  performance.now = () => now;
  window.setTimeout = (f, ms = 0, ...a) => { const id = idc++; q.push({ id, t: now + Math.max(0, +ms || 0), f, a }); return id; };
  window.setInterval = (f, ms = 0, ...a) => { const iv = Math.max(1, +ms || 0); const id = idc++; q.push({ id, t: now + iv, f, a, iv }); return id; };
  window.clearTimeout = window.clearInterval = (id) => { const i = q.findIndex((x) => x.id === id); if (i >= 0) q.splice(i, 1); };
  window.requestAnimationFrame = (f) => window.setTimeout(() => f(now), 16);
  window.cancelAnimationFrame = window.clearTimeout;
  try { Object.defineProperty(window, "devicePixelRatio", { get: () => 2.5 }); } catch {}
  try { window.speechSynthesis.speak = () => {}; window.speechSynthesis.cancel = () => {}; } catch {}
  function runUntil(T) {
    for (let guard = 0; guard < 100000; guard++) {
      q.sort((a, b) => a.t - b.t || a.id - b.id);
      const x = q[0];
      if (!x || x.t > T) break;
      now = x.t;
      if (x.iv) x.t += x.iv; else q.shift();
      try { typeof x.f === "function" ? x.f(...x.a) : null; } catch (e) { console.error(e); }
    }
    now = T;
  }
  const tick = (ms) => new Promise((r) => realST(r, ms));
  window.__seek = async (seconds) => {
    const T = seconds * 1000;
    for (let t = 0; t < T; t += 1000 / 12) { runUntil(Math.min(T, t + 1000 / 12)); await tick(3); }
    runUntil(T); await tick(80); runUntil(T); await tick(30);
    return true;
  };
})();
