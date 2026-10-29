// Cloudflare Worker + Durable Object relay for Fix it together (free plan friendly: SQLite-backed DO).
// Routes:
//   GET  /ws/:code?role=fixer|helper   WebSocket (live mode)
//   GET  /api/rooms/:code/snapshot     latest JPEG frame (snapshot mode)
//   POST /api/rooms/:code/snapshot     Fixer posts a frame (snapshot mode)
//   GET  /api/rooms/:code/messages?role=&after=&pid=   poll messages (snapshot mode)
//   POST /api/rooms/:code/messages?role=&pid=          send a message (snapshot mode)
//   POST /api/rooms/:code/audio        Helper posts a WAV clip (snapshot mode)
//   GET  /j/:code                      web helper (static assets from ../web)
//   GET  /api/health
import { Room, validCode } from "./room.js";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    if (url.pathname === "/api/health") return json({ ok: true, service: "fixit-together-relay" });

    const ws = url.pathname.match(/^\/ws\/([A-Za-z0-9]+)$/);
    const api = url.pathname.match(/^\/api\/rooms\/([A-Za-z0-9]+)\/(snapshot|messages|audio)$/);
    const code = (ws?.[1] || api?.[1] || "").toUpperCase();
    if (ws || api) {
      if (!validCode(code)) return json({ error: "bad code" }, 400);
      const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
      return stub.fetch(request);
    }
    if (url.pathname.startsWith("/j/")) {
      // Single-page web helper: serve index.html for any /j/CODE.
      return env.ASSETS.fetch(new Request(new URL("/index.html", url), request));
    }
    return env.ASSETS.fetch(request);
  },
};

export class RoomObject {
  constructor(state, env) {
    this.state = state;
    this.room = null;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const code = url.pathname.split("/")[2 + (url.pathname.startsWith("/api/") ? 1 : 0)].toUpperCase();
    this.room ??= new Room(code);
    const room = this.room;
    const role = url.searchParams.get("role") === "fixer" ? "fixer" : "helper";

    if (url.pathname.startsWith("/ws/")) {
      if (request.headers.get("Upgrade") !== "websocket") return new Response("expected websocket", { status: 426 });
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      server.accept();
      const conn = { send: (d) => server.send(d), close: (c, r) => server.close(c, r) };
      if (room.join(conn, role, { name: url.searchParams.get("name") || "", lang: url.searchParams.get("lang") || "" })) {
        server.addEventListener("message", (e) => room.message(conn, e.data));
        server.addEventListener("close", () => room.leave(conn));
        server.addEventListener("error", () => room.leave(conn));
      }
      return new Response(null, { status: 101, webSocket: client });
    }

    const kind = url.pathname.split("/").pop();
    const pid = (url.searchParams.get("pid") || "").slice(0, 32);
    if (kind === "snapshot" && request.method === "GET") {
      if (!room.snapshot) return new Response(null, { status: 204, headers: CORS });
      return new Response(room.snapshot.bytes.slice(5), {
        headers: { ...CORS, "Content-Type": "image/jpeg", "Cache-Control": "no-store", "X-Seq": String(room.snapshot.seq) },
      });
    }
    if (kind === "snapshot" && request.method === "POST") {
      return json({ ok: room.httpPostSnapshot(new Uint8Array(await request.arrayBuffer())) });
    }
    if (kind === "audio" && request.method === "GET") {
      const clip = room.httpTakeAudio();
      if (!clip) return new Response(null, { status: 204, headers: CORS });
      return new Response(clip, { headers: { ...CORS, "Content-Type": "application/octet-stream", "Cache-Control": "no-store" } });
    }
    if (kind === "audio" && request.method === "POST") {
      return json({ ok: room.httpPostAudio(new Uint8Array(await request.arrayBuffer())) });
    }
    if (kind === "messages" && request.method === "GET") {
      return json(room.httpMessages(role, Number(url.searchParams.get("after") || 0), pid));
    }
    if (kind === "messages" && request.method === "POST") {
      let msg = null;
      try { msg = await request.json(); } catch {}
      return json({ ok: room.httpPostMessage(role, msg, pid) });
    }
    return json({ error: "not found" }, 404);
  }
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" } });
}
