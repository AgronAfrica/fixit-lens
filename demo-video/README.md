# Fix-it Lens demo video (Remotion)

```sh
npm i
npx remotion render FixitLensDemo out/fixitlens-demo.mp4     # 80 s, 1080x1920, 30 fps
npx remotion render HelperCapture public/real/helper_web_capture.mp4   # re-record the real web helper
```

- `HelperCapture` loads `public/helper/index.html`: the unchanged `together/web` client (bundled to `app.iife.js` with esbuild),
  run in its scripted demo mode with the simulated glasses POV (`pov.js`). `clock.js` replaces timers with a deterministic clock
  and exposes `__seek(seconds)` so each frame is rendered at an exact session time. Rebuild after changing `together/web`:
  `npx esbuild ../together/web/app.js --bundle --format=iife --outfile=public/helper/app.iife.js && cp ../together/web/style.css public/helper/`
- Scenes and frame ranges: `src/demo/timeline.ts`. Captions (no voiceover): `src/demo/captions.ts`.
- Concept clip slots: `public/concept/README.md`. Real iPhone recording slot: `public/real/iphone_fixer_together.mp4` + `IPHONE_RECORDING_READY`.
