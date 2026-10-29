import type { Caption } from "@remotion/captions";

const c = (startS: number, endS: number, text: string): Caption => ({
  text, startMs: startS * 1000, endMs: endS * 1000, timestampMs: startS * 1000, confidence: null,
});

// On-screen captions (there is no voiceover). Times are in the main composition's seconds.
export const CAPTIONS: Caption[] = [
  c(0.3, 5, "A drip, a loose chain, a wobbly hinge: small fixes, if someone shows you how."),
  c(5, 9, "Hands-free: the glasses see what you see."),
  c(9, 13, "Point the camera at what's broken and tap the part."),
  c(13, 17, "SAM 3.1 outlines exactly what you tapped."),
  c(17, 22, "Muse Spark 1.3 diagnoses the fault and writes a step-by-step plan."),
  c(22, 27, "Muse Wonder 1.0 reviews it while Muse Image 1.0 draws the step."),
  c(27, 35, "Ask out loud. Muse Voice Transcribe hears you; the guide answers on the part itself."),
  c(35, 42, "Gas, mains, airbags: the safety stop refuses and sends you to a professional."),
  c(42, 49, "Fix it together: share a code, and a friend joins from any browser."),
  c(49, 56, "Their tap outlines the part on both screens."),
  c(56, 63, "Speech is transcribed and translated, so Spanish and English just work."),
  c(63, 67, "The Fixer hears the helper through the glasses."),
  c(67, 74, "Five Meta models, one repair."),
  c(74, 76.5, "Fix-it Lens. Open source, built during the hackathon."),
];
