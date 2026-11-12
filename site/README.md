# AlwaysOn site

The landing page, served by a Cloudflare Worker with static assets. It fits in the Workers Free plan.

- `public/` holds the page (`index.html`), its styles (`styles.css`), the 404 page, and `images/`. `client/main.js` runs the page with Lenis for smooth scrolling and GSAP ScrollTrigger and SplitText for the motion.
  - A loader turns a status dot from Away to Available, then two bands wipe it away.
  - The hero is a 3D avatar with a status badge (`client/presence.js`) over moving contour lines (`client/contours.js`). The badge fades toward Away yellow as a demo countdown runs out, and each demo input turns it green again. The demo runs 10 times faster than the app, and the page says so. Clicking the avatar sends an input, and dragging spins it. Without WebGL, a flat CSS avatar shows instead.
  - Further down are a pinned reel of screenshots that scrolls sideways, cards for the two input types, a grid of target apps, stacked feature cards, a terminal that types `alwayson run`, and the download section with install steps.
  - The background fades between paper and ink as sections pass. Every colour that depends on it reads `--bg` and `--fg`, set at the top of `styles.css`. Green always means Available and yellow always means Away.
  - With reduced motion, the page skips the loader, smooth scrolling and pinning, and the avatar stays still.
- `public/images/` holds 2x copies of the dark README screenshots. They were made with Real-ESRGAN (`realesrgan-x4plus`, 4x, then scaled down to 2x and saved as WebP at quality 90). Regenerate them when the README screenshots change.
- `build.mjs` copies `public/` and the app icon into `dist/` and bundles `client/main.js` with esbuild, which keeps only the parts of three.js it uses (about 195 KB gzipped). `node build.mjs --watch` rebuilds on every save, which `npm run dev` uses.
- `src/worker.js` serves `dist/` and adds these routes. They're listed under `run_worker_first` in `wrangler.jsonc`; without that, a browser that navigates to one gets the 404 page and the Worker never runs.
  - `/download` sends browsers to `/#download`, where the page skips the loader, shows the download section with the install steps, and starts the download. Other clients, such as curl, are redirected to the DMG.
  - `/download/dmg` redirects to the newest DMG, or to the Releases page if the appcast can't be read.
  - `/latest.json` returns `{ "version", "dmg", "stars" }` for the page. The star count comes from the GitHub API and is cached for 30 minutes; if GitHub refuses, the last known count is used. Set a `GITHUB_TOKEN` secret if lookups fail often.
  - `/e` takes the page's visit counts and passes them to PostHog.

## Visit counts

The page reports a `$pageview` when it loads and `outbound_click` for the download button and links to GitHub and Buy Me a Coffee. The Worker adds `download_started` when the DMG is requested. They go to the same PostHog project as the app's opt-in statistics, with `$lib` set to `alwayson-site`, so PostHog's Web analytics page shows visitors, page views, referrers, and countries.

Nothing is stored in the browser. Visitors are counted by a hash of their address and browser that changes every day, so PostHog never receives the address and can't follow anyone from one day to the next. Requests from bots and from `localhost` aren't counted.

- To make the hash impossible to reverse by guessing addresses, set a secret: `npx wrangler secret put ANALYTICS_SALT`.
- To turn the counts off, remove `POSTHOG_KEY` from `wrangler.jsonc`.

## Develop

```bash
cd site
npm install
npm run dev        # http://localhost:8787
```

## Deploy

```bash
npx wrangler login # once
npm run deploy
```

Pushes to `main` that touch the site or the app icon deploy through `.github/workflows/site.yml`. It needs two repository secrets:

- `CLOUDFLARE_API_TOKEN`: an API token made from the **Edit Cloudflare Workers** template.
- `CLOUDFLARE_ACCOUNT_ID`: the account ID shown on the Workers & Pages overview.

The Worker deploys to `alwayson.<your-subdomain>.workers.dev`. To use your own domain, add it under the Worker's **Settings > Domains & Routes**.
