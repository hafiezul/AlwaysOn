// Serves the landing page from static assets and adds a few routes:
//
//   /download      sends browsers to the page's installer window, which starts
//                  the download and shows the install steps. Anything else
//                  (curl, scripts) is redirected straight to the DMG.
//   /download/dmg  redirects to the latest release's DMG.
//   /latest.json   reports the latest version and the repo's star count.
//   /e             takes the page's anonymous visit counts and passes them to
//                  PostHog. See "Visit counts" below.
//
// The release comes from its Sparkle appcast, which has a stable URL and no
// API rate limit. The star count comes from the GitHub API, which does have
// one, so it's cached for longer and the last known count is kept as a spare.

const REPO = "https://github.com/hafiezul/AlwaysOn";
const REPO_API = "https://api.github.com/repos/hafiezul/AlwaysOn";
const APPCAST_URL = `${REPO}/releases/latest/download/appcast.xml`;
const RELEASES_URL = `${REPO}/releases/latest`;
const RELEASE_CACHE_SECONDS = 600;
const STARS_CACHE_SECONDS = 1800;
const SPARE_CACHE_SECONDS = 7 * 24 * 3600;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === "/download") {
      if (isPageNavigation(request)) return Response.redirect(`${url.origin}/#download`, 302);
      return downloadRedirect(request, env, ctx);
    }

    if (url.pathname === "/download/dmg") return downloadRedirect(request, env, ctx);

    if (url.pathname === "/latest.json") {
      const [latest, stars] = await Promise.all([latestRelease(ctx), starCount(env, ctx)]);
      return Response.json(
        { version: latest?.version ?? null, dmg: latest?.dmg ?? null, stars },
        {
          status: latest ? 200 : 503,
          headers: { "cache-control": `public, max-age=${latest ? RELEASE_CACHE_SECONDS : 60}` },
        },
      );
    }

    if (url.pathname === "/e") return collect(request, env, ctx);

    return env.ASSETS.fetch(request);
  },
};

function isPageNavigation(request) {
  const destination = request.headers.get("sec-fetch-dest");
  if (destination) return destination === "document";
  return (request.headers.get("accept") ?? "").includes("text/html");
}

async function downloadRedirect(request, env, ctx) {
  const latest = await latestRelease(ctx);
  ctx.waitUntil(capture(request, env, "download_started", { version: latest?.version ?? null }));
  return Response.redirect(latest?.dmg ?? RELEASES_URL, 302);
}

// Cached lookups

// Runs `load` at most once per `seconds`. When it fails, the last value that
// worked is served for up to a week, and the failure itself is remembered for
// a minute so a struggling upstream isn't asked again on every request.
async function cached(ctx, name, seconds, load) {
  const cache = caches.default;
  const key = new Request(`https://alwayson.internal/${name}`);
  const spareKey = new Request(`https://alwayson.internal/${name}/spare`);
  const store = (target, value, maxAge) =>
    cache.put(target, Response.json({ value }, { headers: { "cache-control": `public, max-age=${maxAge}` } }));

  const hit = await cache.match(key);
  if (hit) return (await hit.json()).value;

  let value = null;
  try {
    value = await load();
  } catch {}

  if (value !== null) {
    ctx.waitUntil(Promise.all([store(key, value, seconds), store(spareKey, value, SPARE_CACHE_SECONDS)]));
    return value;
  }

  const spare = await cache.match(spareKey);
  value = spare ? (await spare.json()).value : null;
  ctx.waitUntil(store(key, value, 60));
  return value;
}

function latestRelease(ctx) {
  return cached(ctx, "latest-release", RELEASE_CACHE_SECONDS, async () => {
    const response = await fetch(APPCAST_URL, { redirect: "follow" });
    if (!response.ok) return null;

    const xml = await response.text();
    const version = xml.match(/<sparkle:shortVersionString>([^<]+)</)?.[1]?.trim();
    const dmg = xml.match(/<enclosure[^>]*\surl="([^"]+)"/)?.[1];
    if (!version || !dmg?.startsWith(`${REPO}/releases/download/`)) return null;
    return { version, dmg };
  });
}

// GITHUB_TOKEN is optional. Without it GitHub allows 60 requests an hour from
// each address, and Workers share addresses, so a lookup can fail now and then.
function starCount(env, ctx) {
  return cached(ctx, "stars", STARS_CACHE_SECONDS, async () => {
    const headers = { accept: "application/vnd.github+json", "user-agent": "alwayson-site" };
    if (env.GITHUB_TOKEN) headers.authorization = `Bearer ${env.GITHUB_TOKEN}`;
    const response = await fetch(REPO_API, { headers });
    if (!response.ok) return null;
    const count = (await response.json()).stargazers_count;
    return Number.isInteger(count) ? count : null;
  });
}

// Visit counts
//
// The page sends one `$pageview` when it loads and a few named events after
// that. Nothing is stored in the browser: no cookies and no local storage.
// To count visitors, each event carries a hash of the visitor's address and
// browser that changes every day, so the same person can be counted once
// today but can't be followed to tomorrow. PostHog never sees the address,
// is asked not to look up a location, and builds no person profile. The only
// place it learns is the country Cloudflare reports.

const EVENTS = new Set(["$pageview", "window_opened", "outbound_click"]);
const BOTS = /bot|crawl|spider|slurp|headless|lighthouse|preview|monitor|curl|wget|python|scrapy/i;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

async function collect(request, env, ctx) {
  const done = new Response(null, { status: 204 });
  if (request.method !== "POST") return new Response(null, { status: 405, headers: { allow: "POST" } });

  // Only this page may report, and only in a small, known shape
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return new Response(null, { status: 403 });

  let body;
  try {
    body = JSON.parse((await request.text()).slice(0, 4096));
  } catch {
    return new Response(null, { status: 400 });
  }
  if (!body || !EVENTS.has(body.event)) return new Response(null, { status: 400 });

  const text = (value, max = 300) => (typeof value === "string" && value ? value.slice(0, max) : undefined);
  const properties = {
    name: text(body.name, 40),
    $session_id: UUID.test(body.session) ? body.session : undefined,
    $referrer: text(body.referrer) ?? "$direct",
    $referring_domain: hostOf(body.referrer) ?? "$direct",
    $viewport_width: Number.isFinite(body.width) ? Math.round(body.width) : undefined,
    $viewport_height: Number.isFinite(body.height) ? Math.round(body.height) : undefined,
  };

  ctx.waitUntil(capture(request, env, body.event, properties, text(body.url, 500)));
  return done;
}

async function capture(request, env, event, properties = {}, pageURL = null) {
  const url = new URL(request.url);
  const userAgent = request.headers.get("user-agent") ?? "";
  const local = url.hostname === "localhost" || url.hostname === "127.0.0.1";
  if (!env.POSTHOG_KEY || local || !userAgent || BOTS.test(userAgent)) return;

  // The page's own address, kept to this site and stripped of its fragment
  let page = new URL(url.origin);
  try {
    const reported = new URL(pageURL ?? request.headers.get("referer") ?? url.origin);
    if (reported.origin === url.origin) page = reported;
  } catch {}
  page.hash = "";

  const campaign = {};
  for (const name of ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"]) {
    const value = page.searchParams.get(name);
    if (value) campaign[name] = value.slice(0, 100);
  }

  const body = {
    api_key: env.POSTHOG_KEY,
    event,
    distinct_id: await visitorID(request, env, userAgent),
    timestamp: new Date().toISOString(),
    properties: {
      $lib: "alwayson-site",
      $process_person_profile: false,
      $geoip_disable: true,
      $current_url: page.href,
      $host: page.host,
      $pathname: page.pathname,
      $geoip_country_code: request.cf?.country,
      ...describeBrowser(userAgent),
      ...campaign,
      ...properties,
    },
  };

  try {
    await fetch(`${env.POSTHOG_HOST ?? "https://us.i.posthog.com"}/capture/`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {}
}

// The same visitor gets the same ID until midnight UTC, then a new one.
// ANALYTICS_SALT is an optional secret that makes the hash impossible to
// reverse by guessing addresses.
async function visitorID(request, env, userAgent) {
  const day = new Date().toISOString().slice(0, 10);
  const address = request.headers.get("cf-connecting-ip") ?? "";
  const source = [env.ANALYTICS_SALT ?? "", day, address, userAgent].join("|");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(source));
  return [...new Uint8Array(digest).slice(0, 16)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function hostOf(value) {
  try {
    return new URL(value).hostname || undefined;
  } catch {
    return undefined;
  }
}

function describeBrowser(userAgent) {
  const os = /iPhone|iPad|iPod/.test(userAgent)
    ? "iOS"
    : /Android/.test(userAgent)
      ? "Android"
      : /Mac OS X|Macintosh/.test(userAgent)
        ? "Mac OS X"
        : /Windows/.test(userAgent)
          ? "Windows"
          : /CrOS/.test(userAgent)
            ? "Chrome OS"
            : /Linux/.test(userAgent)
              ? "Linux"
              : "Other";
  const browser = /Edg\//.test(userAgent)
    ? "Microsoft Edge"
    : /OPR\//.test(userAgent)
      ? "Opera"
      : /Firefox\//.test(userAgent)
        ? "Firefox"
        : /Chrome\//.test(userAgent)
          ? "Chrome"
          : /Safari\//.test(userAgent)
            ? "Safari"
            : "Other";
  const device = /iPad|Tablet/.test(userAgent) ? "Tablet" : /Mobi|iPhone|Android/.test(userAgent) ? "Mobile" : "Desktop";
  return { $os: os, $browser: browser, $device_type: device };
}
