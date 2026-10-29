// Where the relay lives. Empty = same origin (Cloudflare Worker or `node server.mjs` serve this page).
// Deployed relay (Cloudflare Worker + Durable Object). A ?relay=https://... query parameter overrides it.
window.FIXIT_RELAY = "https://fixit-together.joinreson.workers.dev";
