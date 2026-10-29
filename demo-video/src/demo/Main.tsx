import React from "react";
import { AbsoluteFill, Sequence, interpolate, useCurrentFrame } from "remotion";
import { C } from "./theme";
import { SCENES, CONCEPT_SLOTS } from "./timeline";
import { CONCEPT_CLIPS_READY } from "./theme";
import { CaptionTrack, ConceptSlot } from "./ui";
import { EndCard, Hook, ModelsScene, PipelineScene, SafetyScene, TapScene, TogetherScene, VoiceScene } from "./scenes";

const Fade: React.FC<{ dur: number; children: React.ReactNode }> = ({ dur, children }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [0, 8, dur - 8, dur], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return <AbsoluteFill style={{ opacity: o }}>{children}</AbsoluteFill>;
};

const S: React.FC<{ k: keyof typeof SCENES; children: React.ReactNode; name: string }> = ({ k, children, name }) => (
  <Sequence from={SCENES[k].from} durationInFrames={SCENES[k].dur} premountFor={30} name={name}>
    <Fade dur={SCENES[k].dur}>{children}</Fade>
  </Sequence>
);

export const FixitLensDemo: React.FC = () => (
  <AbsoluteFill style={{ background: C.night }}>
    <S k="hook" name="Hook">{<Hook />}</S>
    <S k="conceptA" name="Concept slot A">
      <ConceptSlot {...CONCEPT_SLOTS.conceptA} ready={CONCEPT_CLIPS_READY} caption="Hands-free: the glasses see what you see." />
    </S>
    <S k="tap" name="Lens · tap"><TapScene /></S>
    <S k="pipeline" name="Pipeline"><PipelineScene /></S>
    <S k="voice" name="Voice guide"><VoiceScene /></S>
    <S k="safety" name="Safety stop"><SafetyScene /></S>
    <S k="together" name="Fix it together"><TogetherScene /></S>
    <S k="conceptB" name="Concept slot B">
      <ConceptSlot {...CONCEPT_SLOTS.conceptB} ready={CONCEPT_CLIPS_READY} caption="The Fixer hears the helper through the glasses." />
    </S>
    <S k="models" name="5 Meta models"><ModelsScene /></S>
    <S k="end" name="End card"><EndCard /></S>
    <CaptionTrack />
  </AbsoluteFill>
);
