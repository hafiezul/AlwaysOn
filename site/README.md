# AlwaysOn site

The landing page, served by a Cloudflare Worker with static assets. It fits in the Workers Free plan.

- `public/` holds the page, styles, and `main.js`. The page is a Mac, and each thing has one way in. The Dock is the only launcher: one item per feature window (Read Me, Pulse Log, Keep Online Until, Activity, Settings, Terminal, Install), plus the windows minimized into it. The menu bar holds the app's name (About and Check for Updates), Star and Buy me a coffee, the AlwaysOn menu, which is a working copy that controls the demo session, and Wi-Fi, Battery and Control Center. Windows drag, resize, zoom, minimize and close, and only they scroll. Visitors arrive to the AlwaysOn menu, open under its icon, and no windows. The first time it closes, a note points at the icon until it's opened again. Activity is a working copy of the app's Settings pane: today's bar grows as the demo keeps you online, coloured by what started the session, pointing at a day shows its breakdown, and Clear History asks first in a sheet. Lock Screen, in Control Center, pauses the demo the way a locked Mac pauses the app. Notifications slide in under the menu bar. In the stacked page the menu moves into the Read Me, under the download button. On screens narrower than 900px or shorter than 600px, the windows stack into a normal scrolling page with no Dock. `main.js` runs the working copies of the AlwaysOn menu and the Pulse Log window, plus the input picker in Settings, the Keep Online Until window, the terminal, and the installer window, where dragging the app into Applications starts the download.
- Each window is a CSS container named `win`, so its contents lay out by the window's own width: a zoomed Read Me goes to two columns and a small window stacks.
- Two easter eggs: the Konami code sweeps the wallpaper with colour, and a visitor who leaves the page alone for a real minute is told what Teams would have done to their status.
- The desktop is empty. A right-click on it offers New Folder and Clean Up, and the folders can be dragged, alone or as a selection.
- The right of the menu bar works too, and each control changes something the app reacts to. Joining a network in the Wi-Fi menu switches profiles, once the running session ends. Low Power Mode, in the battery menu, doubles the time between inputs. Control Center has a Focus that starts a session of its own, Dark Mode, and the lock screen. The battery level is the visitor's own where the browser reports it.
- The page is dark unless the visitor turns Dark Mode off in Control Center, which is remembered in `localStorage`. Every colour that differs between the two is a variable at the top of `styles.css`; the light values sit under `:root[data-theme="light"]`. The terminal and the lock screen stay dark in both. The app's screenshots switch to their light versions.
- Colors are macOS system colors, each with one meaning taken from the app: the accent blue for buttons and selection, green for posted input, orange for skipped, indigo for a sleeping Mac, red for problems. Yellow marks Away, on the headline's second dot.
- `client/hero3d.js` draws the hero's wallpaper as a 3D field of pixel blocks with three.js. `main.js` loads it only when WebGL works and the visitor allows motion; otherwise a flat grid shows instead. It has a palette for each appearance.
- `build.mjs` copies `public/`, the README screenshots, and the app icon into `dist/`, so the site always shows the same images as the README. It also bundles `client/hero3d.js` with esbuild, which keeps only the parts of three.js it uses (about 135 KB gzipped).
- `src/worker.js` serves `dist/` and adds these routes. They're listed under `run_worker_first` in `wrangler.jsonc`; without that, a browser that navigates to one gets the 404 page and the Worker never runs.
  - `/download` sends browsers to `/#download`, where the page opens the installer window and starts the download. Other clients, such as curl, are redirected to the DMG.
  - `/download/dmg` redirects to the newest DMG, or to the Releases page if the appcast can't be read.
  - `/latest.json` returns `{ "version", "dmg", "stars" }` for the page. The star count comes from the GitHub API and is cached for 30 minutes; if GitHub refuses, the last known count is used. Set a `GITHUB_TOKEN` secret if lookups fail often.
  - `/e` takes the page's visit counts and passes them to PostHog.

## Visit counts

The page reports a `$pageview` when it loads, `window_opened` when a visitor opens a window, and `outbound_click` for links to GitHub and Buy Me a Coffee. The Worker adds `download_started` when the DMG is requested. They go to the same PostHog project as the app's opt-in statistics, with `$lib` set to `alwayson-site`, so PostHog's Web analytics page shows visitors, page views, referrers, and countries.

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

Pushes to `main` that touch the site, the screenshots, or the app icon deploy through `.github/workflows/site.yml`. It needs two repository secrets:

- `CLOUDFLARE_API_TOKEN`: an API token made from the **Edit Cloudflare Workers** template.
- `CLOUDFLARE_ACCOUNT_ID`: the account ID shown on the Workers & Pages overview.

The Worker deploys to `alwayson.<your-subdomain>.workers.dev`. To use your own domain, add it under the Worker's **Settings > Domains & Routes**.
