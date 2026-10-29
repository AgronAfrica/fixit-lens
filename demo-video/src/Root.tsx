import { Composition } from "remotion";
import { HelperCapture } from "./HelperCapture";
import { FixitLensDemo } from "./demo/Main";
import { TOTAL, FPS } from "./demo/timeline";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition id="FixitLensDemo" component={FixitLensDemo} durationInFrames={TOTAL} fps={FPS} width={1080} height={1920} />
      {/* Records the real together/web helper client (scripted demo + simulated glasses feed) to public/real/helper_web_capture.mp4 */}
      <Composition id="HelperCapture" component={HelperCapture} durationInFrames={21 * 30} fps={30} width={1080} height={1920} />
    </>
  );
};
