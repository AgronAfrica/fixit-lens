# Fix it together

A Fixer (the person at the broken thing, on the iPhone app, optionally wearing Ray-Ban Meta glasses) shares a 6-character code or link. A Helper joins from the app or from any browser. Both see the live camera, either one taps to outline a part with SAM 3.1, and speech is transcribed (Muse Voice Transcribe), translated (Muse Spark 1.3) and shown as captions plus spoken on-device.

**All Meta calls run on the Fixer's phone with the Fixer's key.** The relay and the web helper never see a Meta key. The relay only forwards frames, taps, masks and captions inside a room.

```
together/
  relay/   WebSocket relay: Cloudflare Worker + Durable Object (src/), or plain Node (server.mjs). npm test = protocol tests.
  web/     Static helper client (index.html, app.js, lib.js, demo.js, style.css). vercel.json for Vercel hosting.
```

## Live deployment

- Relay: `https://fixit-together.joinreson.workers.dev` (health: `/api/health`, WebSocket: `wss://fixit-together.joinreson.workers.dev/ws/CODE?role=fixer|helper`, join links: `/j/CODE`).
- Web helper (Vercel): `https://fixit-lens-together.vercel.app` (`web/config.js` points `window.FIXIT_RELAY` at the relay).
- The iOS app uses this relay by default; **Settings → Fix it together → Relay URL** overrides it.

## Deploy your own (free tiers)

You need a **Cloudflare account** (Workers free plan). Vercel is optional.

1. `cd together/relay && npm install`
2. `npx wrangler login` (opens the browser), then `npx wrangler deploy`. Wrangler prints the URL, e.g. `https://fixit-together.<you>.workers.dev`. That one Worker serves the relay **and** the web helper (`/j/CODE`).
3. In the app: **Settings → Fix it together → Relay URL** = that URL (or change `AppModel.defaultRelayURL`).
4. Optional, Vercel for the web helper: import `together/web` as a static project, set `window.FIXIT_RELAY` in `web/config.js` to the Worker URL, deploy. `vercel.json` rewrites `/j/:code` to the client.

Local: `cd together/relay && npm start` (Node, port 8787, serves `../web` too). Phones on the same Wi-Fi can use `http://<your-mac-ip>:8787`.

## Transport

- Live: WebSocket, JPEG frames paced by acks (no queue build-up on slow links), taps/masks/captions as JSON.
- Snapshot fallback: if WebSockets fail, the helper polls an HTTP snapshot about once a second (`Snapshot mode · 1 frame/s`).
- Rooms live in memory only (the latest frame is kept for late joiners; nothing is written to disk or Durable Object storage). The Node relay drops rooms after 2 hours idle.

## Demo mode (no phone, no relay, no key)

Open `web/index.html?demo=1` (add `&pov=1` for the simulated glasses feed). A **scripted** Fixer plays a Spanish-speaking session. Everything is labelled on screen as *Demo mode · scripted session*; outlines are hand-placed boxes from the app's demo library, not SAM output. The app has the same: **Fix it together → Two-device demo (scripted helper)**.

## Repair memory

When the session ends, the Fixer can save it. Muse Spark 1.3 turns the captions into a short titled checklist, kept on the phone (Repair memory in the lobby) and replayable later.

## Safety

The app's local SafetyGuard runs on every transcript in a session. A stop shows a banner on both screens and no steps are given.
