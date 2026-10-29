// One place for the scene layout (30 fps). Frame ranges here are what the README reports.
export const FPS = 30;
export const SCENES = {
  hook: { from: 0, dur: 150 },
  conceptA: { from: 150, dur: 120 },
  tap: { from: 270, dur: 240 },
  pipeline: { from: 510, dur: 300 },
  voice: { from: 810, dur: 240 },
  safety: { from: 1050, dur: 210 },
  together: { from: 1260, dur: 630 },
  conceptB: { from: 1890, dur: 120 },
  models: { from: 2010, dur: 210 },
  end: { from: 2220, dur: 180 },
} as const;
export const TOTAL = 2400;

export const CONCEPT_SLOTS = {
  conceptA: { file: "concept/glasses_wearer_sink.mp4", from: 150, to: 269, seconds: 4,
    brief: "Person wearing Ray-Ban Meta glasses kneels at a leaking sink trap, looks at it hands-free." },
  conceptB: { file: "concept/glasses_wearer_together.mp4", from: 1890, to: 2009, seconds: 4,
    brief: "Same person, glasses on, turns the slip nut by hand while listening to a remote helper." },
} as const;
