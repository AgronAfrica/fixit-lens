// Where the relay lives. Empty = same origin (Cloudflare Worker or `node server.mjs` serve this page).
// When this folder is hosted on Vercel, set it to your Worker URL, e.g. "https://fixit-together.<you>.workers.dev".
// A ?relay=https://... query parameter overrides it.
window.FIXIT_RELAY = "";
