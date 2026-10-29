import { useCallback, useLayoutEffect, useRef } from "react";
import { AbsoluteFill, delayRender, continueRender, staticFile, useCurrentFrame, useVideoConfig } from "remotion";

/**
 * Records the REAL Fix it together web client (together/web, bundled unchanged) in its labelled demo
 * mode with the simulated glasses feed. Each video frame reloads the page and seeks its deterministic
 * clock (public/helper/clock.js) to that moment, so the output is what the browser shows t seconds in.
 */
export const HelperCapture: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const ref = useRef<HTMLIFrameElement>(null);
  const pending = useRef<{ frame: number; handle: number } | null>(null);

  useLayoutEffect(() => {
    if (pending.current) continueRender(pending.current.handle);
    pending.current = { frame, handle: delayRender(`helper frame ${frame}`, { timeoutInMilliseconds: 60000 }) };
  }, [frame]);

  const onLoad = useCallback(async () => {
    const p = pending.current;
    const win = ref.current?.contentWindow as (Window & { __seek?: (s: number) => Promise<boolean> }) | null;
    if (!p) return;
    if (win?.__seek) await win.__seek(p.frame / fps);
    if (pending.current === p) {
      continueRender(p.handle);
      pending.current = null;
    }
  }, [fps]);

  return (
    <AbsoluteFill style={{ backgroundColor: "#06070A" }}>
      <iframe
        key={frame}
        ref={ref}
        onLoad={onLoad}
        src={`${staticFile("helper/index.html")}?demo=1&pov=1&f=${frame}`}
        style={{ width: 432, height: 768, border: 0, transformOrigin: "0 0", scale: "2.5" }}
      />
    </AbsoluteFill>
  );
};
