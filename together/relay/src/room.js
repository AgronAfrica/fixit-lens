// Fix it together: one room per join code. Shared by the Cloudflare Durable Object (worker.js)
// and the local Node server (server.mjs). No Meta API calls happen here: all model calls run on
// the Fixer's phone, so the relay never sees a key. It only forwards messages and frames.

export const MAX_PEERS = 4;
export const LIMITS = { text: 64 * 1024, frame: 512 * 1024, audio: 2 * 1024 * 1024 };
export const KIND = { JPEG: 0x01, WAV: 0x02 };
const CODE = /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4,8}$/;
const LOG_SIZE = 120;

export function validCode(code) {
  return typeof code === "string" && CODE.test(code);
}

/**
 * A connection is any object with send(stringOrUint8Array) and close(code, reason).
 * HTTP-polling peers (snapshot mode) don't hold a connection; they read the logs instead.
 */
export class Room {
  constructor(code, now = () => Date.now()) {
    this.code = code;
    this.now = now;
    this.peers = new Map(); // conn -> {id, role, name, lang, platform}
    this.nextId = 1;
    this.snapshot = null; // {seq, bytes: Uint8Array, at}
    this.logs = { helper: [], fixer: [] }; // messages for HTTP-polling peers
    this.msgSeq = 0;
    this.lastActivity = now();
    this.pollers = new Map(); // pollerId -> {role, name, lang, seen}
    this.audioQueue = []; // helper WAV clips waiting for a Fixer that is polling
  }

  get fixer() {
    for (const [conn, p] of this.peers) if (p.role === "fixer") return conn;
    return null;
  }

  count() {
    return this.peers.size + [...this.pollers.values()].filter((p) => this.now() - p.seen < 5000).length;
  }

  join(conn, role, meta = {}) {
    this.lastActivity = this.now();
    if (role !== "fixer" && role !== "helper") {
      conn.close(4400, "bad role");
      return false;
    }
    if (role === "fixer") {
      const old = this.fixer;
      if (old) {
        this.peers.delete(old);
        try { old.close(4001, "replaced by a new Fixer connection"); } catch {}
      }
    } else if (this.count() >= MAX_PEERS) {
      conn.close(4429, "room full");
      return false;
    }
    this.peers.set(conn, { id: this.nextId++, role, name: (meta.name || role).slice(0, 40), lang: meta.lang || "", platform: meta.platform || "" });
    this.broadcastPeers();
    if (role === "helper" && !this.fixer) this.sendTo(conn, { t: "status", text: "Waiting for the Fixer to start the session…" });
    if (role === "helper" && this.snapshot) conn.send(this.snapshot.bytes);
    return true;
  }

  leave(conn) {
    if (!this.peers.has(conn)) return;
    const peer = this.peers.get(conn);
    this.peers.delete(conn);
    if (peer.role === "fixer") this.toHelpers({ t: "status", text: "The Fixer disconnected. Waiting for them to come back…" });
    this.broadcastPeers();
  }

  message(conn, data) {
    this.lastActivity = this.now();
    const peer = this.peers.get(conn);
    if (!peer) return;
    if (typeof data === "string") {
      if (data.length > LIMITS.text) return;
      let msg;
      try { msg = JSON.parse(data); } catch { return; }
      if (!msg || typeof msg.t !== "string") return;
      if (msg.t === "hello") {
        Object.assign(peer, {
          name: String(msg.name || peer.name).slice(0, 40),
          lang: String(msg.lang || peer.lang).slice(0, 24),
          platform: String(msg.platform || peer.platform).slice(0, 24),
        });
        this.broadcastPeers();
        // Tell the Fixer who joined, so it can translate for them.
        if (peer.role === "helper") this.toFixer({ ...msg, id: peer.id });
        return;
      }
      if (peer.role === "fixer") this.toHelpers(msg);
      else this.toFixer({ ...msg, from: peer.id, name: peer.name });
      return;
    }
    const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
    if (bytes.length < 5) return;
    const kind = bytes[0];
    if (peer.role === "fixer" && kind === KIND.JPEG && bytes.length <= LIMITS.frame) {
      this.snapshot = { seq: seqOf(bytes), bytes, at: this.now() };
      for (const [c, p] of this.peers) if (p.role === "helper") safeSend(c, bytes);
    } else if (peer.role === "helper" && kind === KIND.WAV && bytes.length <= LIMITS.audio) {
      const fixer = this.fixer;
      if (fixer) safeSend(fixer, bytes);
      else this.queueAudio(bytes);
    }
  }

  // ---- HTTP fallback (snapshot mode): used when a WebSocket can't be held open.

  httpPostSnapshot(bytes) {
    if (bytes.length < 5 || bytes[0] !== KIND.JPEG || bytes.length > LIMITS.frame) return false;
    this.lastActivity = this.now();
    this.snapshot = { seq: seqOf(bytes), bytes, at: this.now() };
    for (const [c, p] of this.peers) if (p.role === "helper") safeSend(c, bytes);
    return true;
  }

  httpPostMessage(role, msg, pollerId) {
    if (!msg || typeof msg.t !== "string") return false;
    this.lastActivity = this.now();
    if (pollerId) this.touchPoller(pollerId, role, msg);
    if (role === "fixer") this.toHelpers(msg);
    else this.toFixer({ ...msg, from: `poll-${pollerId || "anon"}` });
    return true;
  }

  httpPostAudio(bytes) {
    if (bytes.length < 5 || bytes[0] !== KIND.WAV || bytes.length > LIMITS.audio) return false;
    this.lastActivity = this.now();
    const fixer = this.fixer;
    if (fixer) safeSend(fixer, bytes);
    else this.queueAudio(bytes);
    return true;
  }

  /** A Fixer in snapshot mode collects helper voice clips here (oldest first). */
  httpTakeAudio() {
    return this.audioQueue.shift() || null;
  }

  queueAudio(bytes) {
    this.audioQueue.push(bytes);
    if (this.audioQueue.length > 4) this.audioQueue.shift();
  }

  httpMessages(role, after, pollerId) {
    if (pollerId) this.touchPoller(pollerId, role);
    const log = role === "fixer" ? this.logs.fixer : this.logs.helper;
    return { messages: log.filter((m) => m.n > after), last: this.msgSeq, peers: this.peerSummary() };
  }

  touchPoller(id, role, msg) {
    const p = this.pollers.get(id) || { role, name: role, lang: "" };
    p.seen = this.now();
    if (msg && msg.t === "hello") Object.assign(p, { name: String(msg.name || p.name).slice(0, 40), lang: String(msg.lang || "") });
    this.pollers.set(id, p);
  }

  // ---- routing

  toHelpers(msg) {
    const text = JSON.stringify(msg);
    this.log("helper", msg);
    for (const [c, p] of this.peers) if (p.role === "helper") safeSend(c, text);
  }

  toFixer(msg) {
    this.log("fixer", msg);
    const fixer = this.fixer;
    if (fixer) safeSend(fixer, JSON.stringify(msg));
  }

  sendTo(conn, msg) {
    safeSend(conn, JSON.stringify(msg));
  }

  log(side, msg) {
    if (msg.t === "ack") return; // acks are only meaningful on a live socket
    const entry = { ...msg, n: ++this.msgSeq };
    const log = this.logs[side];
    log.push(entry);
    if (log.length > LOG_SIZE) log.shift();
  }

  peerSummary() {
    const helpers = [...this.peers.values()].filter((p) => p.role === "helper").map((p) => p.name);
    for (const p of this.pollers.values()) if (p.role === "helper" && this.now() - p.seen < 5000) helpers.push(p.name);
    return { count: helpers.length + (this.fixer ? 1 : 0), helpers, fixer: !!this.fixer };
  }

  broadcastPeers() {
    const s = this.peerSummary();
    const text = JSON.stringify({ t: "peers", count: s.count, helpers: s.helpers, fixer: s.fixer });
    for (const c of this.peers.keys()) safeSend(c, text);
  }

  idleFor() {
    return this.now() - this.lastActivity;
  }
}

export function seqOf(bytes) {
  return ((bytes[1] << 24) >>> 0) + (bytes[2] << 16) + (bytes[3] << 8) + bytes[4];
}

function safeSend(conn, data) {
  try { conn.send(data); } catch {}
}
