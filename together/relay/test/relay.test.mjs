import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import WebSocket from "ws";
import { Room, validCode, seqOf, KIND } from "../src/room.js";
import { normalizeCode, mediaFrame, parseMedia, encodeWav, containRect } from "../../web/lib.js";

const PORT = 18787 + Math.floor(Math.random() * 1000);
const BASE = `http://127.0.0.1:${PORT}`;

test("codes", () => {
  assert.equal(normalizeCode("k7m-2qx"), "K7M2QX");
  assert.equal(normalizeCode("O0I1"), null);
  assert.ok(validCode("K7M2QX"));
  assert.ok(!validCode("../x"));
});

test("media framing and WAV", () => {
  const f = mediaFrame(KIND.JPEG, 4242, new Uint8Array([9, 8, 7]));
  assert.equal(seqOf(f), 4242);
  const p = parseMedia(f);
  assert.deepEqual([p.kind, p.seq, [...p.payload]], [1, 4242, [9, 8, 7]]);
  const wav = encodeWav([new Float32Array(48000).fill(0.5)], 48000, 16000);
  assert.equal(new TextDecoder().decode(wav.slice(0, 4)), "RIFF");
  assert.equal(wav.length, 44 + 16000 * 2);
  const r = containRect(9, 16, 100, 100);
  assert.ok(Math.abs(r.h - 100) < 1e-9 && r.x > 0);
});

test("room routing and limits", () => {
  const room = new Room("ABCD");
  const box = () => ({ got: [], closed: null, send(d) { this.got.push(d); }, close(c) { this.closed = c; } });
  const fixer = box(), h1 = box(), extra = [box(), box(), box()];
  assert.ok(room.join(fixer, "fixer", { name: "F" }));
  assert.ok(room.join(h1, "helper", { name: "H1" }));
  room.message(h1, JSON.stringify({ t: "tap", x: 0.5, y: 0.5, seq: 1 }));
  const tap = fixer.got.map((d) => typeof d === "string" && JSON.parse(d)).find((m) => m && m.t === "tap");
  assert.equal(tap.name, "H1");
  room.message(fixer, mediaFrame(KIND.JPEG, 7, new Uint8Array(10)));
  assert.ok(h1.got.some((d) => d instanceof Uint8Array && seqOf(d) === 7));
  assert.equal(room.snapshot.seq, 7);
  room.message(h1, mediaFrame(KIND.JPEG, 8, new Uint8Array(10)));
  assert.equal(room.snapshot.seq, 7);
  room.join(extra[0], "helper", {}); room.join(extra[1], "helper", {});
  assert.equal(room.join(extra[2], "helper", {}), false);
  assert.equal(extra[2].closed, 4429);
  room.message(fixer, JSON.stringify({ t: "caption", caption: { original: "hola" } }));
  const polled = room.httpMessages("helper", 0, "p1");
  assert.ok(polled.messages.some((m) => m.t === "caption"));
  assert.equal(room.httpMessages("helper", polled.last, "p1").messages.length, 0);
});

test("node relay end to end (WebSocket live + HTTP snapshot)", async (t) => {
  const srv = spawn(process.execPath, ["server.mjs"], { env: { ...process.env, PORT: String(PORT) }, stdio: "pipe" });
  t.after(() => srv.kill());
  for (let i = 0; i < 50; i++) { try { if ((await fetch(`${BASE}/api/health`)).ok) break; } catch {} await wait(100); }
  const open = (role, name) => new Promise((res, rej) => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws/TEST42?role=${role}&name=${name}`);
    ws.inbox = [];
    ws.on("message", (d, bin) => ws.inbox.push(bin ? new Uint8Array(d) : JSON.parse(d.toString())));
    ws.on("open", () => res(ws));
    ws.on("error", rej);
  });
  const fixer = await open("fixer", "F");
  const helper = await open("helper", "H");
  fixer.send(Buffer.from(mediaFrame(KIND.JPEG, 1, new Uint8Array([0xff, 0xd8, 0xff]))));
  helper.send(JSON.stringify({ t: "tap", x: 0.4, y: 0.6, seq: 1 }));
  helper.send(Buffer.from(mediaFrame(KIND.WAV, 2, new Uint8Array(100))));
  await wait(300);
  assert.ok(helper.inbox.some((m) => m instanceof Uint8Array && m[0] === KIND.JPEG));
  assert.ok(fixer.inbox.some((m) => m.t === "tap" && m.name === "H"));
  assert.ok(fixer.inbox.some((m) => m instanceof Uint8Array && m[0] === KIND.WAV));
  const snap = await fetch(`${BASE}/api/rooms/TEST42/snapshot`);
  assert.equal(snap.status, 200);
  assert.equal(snap.headers.get("x-seq"), "1");
  fixer.send(JSON.stringify({ t: "mask", mask: { box: [0.1, 0.1, 0.2, 0.2], label: "slip nut" } }));
  await wait(200);
  const msgs = await (await fetch(`${BASE}/api/rooms/TEST42/messages?role=helper&after=0&pid=p`)).json();
  assert.ok(msgs.messages.some((m) => m.t === "mask"));
  const page = await fetch(`${BASE}/j/TEST42`);
  assert.match(await page.text(), /Fix it together/);
  fixer.close(); helper.close();
});

test("helper audio waits for a polling fixer", () => {
  const room = new Room("WXYZ");
  const helper = { send() {}, close() {} };
  room.join(helper, "helper", { name: "H" });
  room.message(helper, mediaFrame(KIND.WAV, 3, new Uint8Array(20)));
  assert.equal(room.httpTakeAudio()?.[0], KIND.WAV);
  assert.equal(room.httpTakeAudio(), null);
});
