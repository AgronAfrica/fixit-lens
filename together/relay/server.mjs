// Local / self-hosted relay with the same protocol as the Cloudflare Worker.
//   npm install && npm start            -> http://localhost:8787  (web helper at /j/CODE)
// Works on a LAN with no accounts: point the app's Relay URL at http://<your-mac-ip>:8787.
import http from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";
import { Room, validCode } from "./src/room.js";

const PORT = Number(process.env.PORT || 8787);
const WEB = fileURLToPath(new URL("../web/", import.meta.url));
const rooms = new Map();
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".jpg": "image/jpeg", ".png": "image/png", ".svg": "image/svg+xml", ".json": "application/json", ".webmanifest": "application/manifest+json" };
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,POST,OPTIONS", "Access-Control-Allow-Headers": "Content-Type" };

function room(code) {
  if (!rooms.has(code)) rooms.set(code, new Room(code));
  return rooms.get(code);
}

setInterval(() => {
  for (const [code, r] of rooms) if (r.peers.size === 0 && r.idleFor() > 2 * 60 * 60 * 1000) rooms.delete(code);
}, 60_000).unref();

function send(res, status, body, headers = {}) {
  res.writeHead(status, { ...CORS, ...headers });
  res.end(body);
}

async function body(req, limit) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > limit) throw new Error("too large");
    chunks.push(c);
  }
  return Buffer.concat(chunks);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  if (req.method === "OPTIONS") return send(res, 204, "");
  if (url.pathname === "/api/health") return send(res, 200, JSON.stringify({ ok: true, service: "fixit-together-relay", rooms: rooms.size }), { "Content-Type": "application/json" });

  const api = url.pathname.match(/^\/api\/rooms\/([A-Za-z0-9]+)\/(snapshot|messages|audio)$/);
  if (api) {
    const code = api[1].toUpperCase();
    if (!validCode(code)) return send(res, 400, '{"error":"bad code"}');
    const r = room(code);
    const role = url.searchParams.get("role") === "fixer" ? "fixer" : "helper";
    const pid = (url.searchParams.get("pid") || "").slice(0, 32);
    const json = (o) => send(res, 200, JSON.stringify(o), { "Content-Type": "application/json", "Cache-Control": "no-store" });
    try {
      if (api[2] === "snapshot" && req.method === "GET") {
        if (!r.snapshot) return send(res, 204, "");
        return send(res, 200, Buffer.from(r.snapshot.bytes.slice(5)), { "Content-Type": "image/jpeg", "Cache-Control": "no-store", "X-Seq": String(r.snapshot.seq) });
      }
      if (api[2] === "snapshot") return json({ ok: r.httpPostSnapshot(new Uint8Array(await body(req, 600_000))) });
      if (api[2] === "audio" && req.method === "GET") {
        const clip = r.httpTakeAudio();
        return clip ? send(res, 200, Buffer.from(clip), { "Content-Type": "application/octet-stream", "Cache-Control": "no-store" }) : send(res, 204, "");
      }
      if (api[2] === "audio") return json({ ok: r.httpPostAudio(new Uint8Array(await body(req, 2_200_000))) });
      if (req.method === "GET") return json(r.httpMessages(role, Number(url.searchParams.get("after") || 0), pid));
      let msg = null;
      try { msg = JSON.parse((await body(req, 70_000)).toString("utf8")); } catch {}
      return json({ ok: r.httpPostMessage(role, msg, pid) });
    } catch {
      return send(res, 413, '{"error":"too large"}');
    }
  }

  // Static web helper.
  let path = url.pathname.startsWith("/j/") || url.pathname === "/" ? "/index.html" : url.pathname;
  path = normalize(path).replace(/^(\.\.[/\\])+/, "");
  try {
    const file = await readFile(join(WEB, path));
    send(res, 200, file, { "Content-Type": TYPES[extname(path)] || "application/octet-stream" });
  } catch {
    send(res, 404, "not found");
  }
});

const wss = new WebSocketServer({ noServer: true, maxPayload: 2_200_000 });
server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url, "http://localhost");
  const m = url.pathname.match(/^\/ws\/([A-Za-z0-9]+)$/);
  const code = m?.[1]?.toUpperCase();
  if (!code || !validCode(code)) return socket.destroy();
  wss.handleUpgrade(req, socket, head, (ws) => {
    const r = room(code);
    const conn = { send: (d) => ws.send(d), close: (c, reason) => ws.close(c, reason) };
    const role = url.searchParams.get("role") === "fixer" ? "fixer" : "helper";
    if (!r.join(conn, role, { name: url.searchParams.get("name") || "", lang: url.searchParams.get("lang") || "" })) return;
    ws.on("message", (data, isBinary) => r.message(conn, isBinary ? new Uint8Array(data) : data.toString("utf8")));
    ws.on("close", () => r.leave(conn));
    ws.on("error", () => r.leave(conn));
  });
});

server.listen(PORT, () => console.log(`Fix it together relay on http://localhost:${PORT}  (web helper: /j/CODE)`));
