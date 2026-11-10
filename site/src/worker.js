// Serves the landing page from static assets and adds two routes that follow
// the latest GitHub release: /download redirects to its DMG, and /latest.json
// reports its version for the page. Both read the release's Sparkle appcast,
// which has a stable URL and no API rate limit.

const REPO = "https://github.com/hafiezul/AlwaysOn";
const APPCAST_URL = `${REPO}/releases/latest/download/appcast.xml`;
const RELEASES_URL = `${REPO}/releases/latest`;
const CACHE_SECONDS = 600;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === "/download") {
      const latest = await latestRelease(ctx);
      return Response.redirect(latest?.dmg ?? RELEASES_URL, 302);
    }

    if (url.pathname === "/latest.json") {
      const latest = await latestRelease(ctx);
      return Response.json(latest ?? { version: null, dmg: null }, {
        status: latest ? 200 : 503,
        headers: { "cache-control": `public, max-age=${CACHE_SECONDS}` },
      });
    }

    return env.ASSETS.fetch(request);
  },
};

async function latestRelease(ctx) {
  const cache = caches.default;
  const key = new Request("https://alwayson.internal/latest-release");

  const cached = await cache.match(key);
  if (cached) return cached.json();

  try {
    const response = await fetch(APPCAST_URL, { redirect: "follow" });
    if (!response.ok) return null;

    const xml = await response.text();
    const version = xml.match(/<sparkle:shortVersionString>([^<]+)</)?.[1]?.trim();
    const dmg = xml.match(/<enclosure[^>]*\surl="([^"]+)"/)?.[1];
    if (!version || !dmg?.startsWith(`${REPO}/releases/download/`)) return null;

    const latest = { version, dmg };
    ctx.waitUntil(
      cache.put(
        key,
        Response.json(latest, {
          headers: { "cache-control": `public, max-age=${CACHE_SECONDS}` },
        }),
      ),
    );
    return latest;
  } catch {
    return null;
  }
}
