# AlwaysOn site

The landing page, served by a Cloudflare Worker with static assets. It fits in the Workers Free plan.

- `public/` holds the page, styles, and `main.js`. The page is a Mac: the nav is the menu bar, and the viewport is a desktop with icons and windows that open, drag, zoom, and close. Only the windows scroll. Visitors arrive to just the Read Me window; the AlwaysOn menu opens from the menu bar icon (a note points to it until it's opened once), and everything else opens from the desktop icons. A status line in the Read Me shows the demo's latest attempt and opens the menu too. In the stacked page the menu moves into the Read Me, under the download button. On screens narrower than 900px or shorter than 600px, the windows stack into a normal scrolling page. `main.js` runs the working copies of the AlwaysOn menu and the Pulse Log window, plus the input picker in Settings, the Keep Online Until window, and the terminal.
- Colors are macOS system colors, each with one meaning taken from the app: the accent blue for buttons and selection, green for posted input, orange for skipped, indigo for a sleeping Mac, red for problems. Yellow marks Away, on the headline's second dot.
- `client/hero3d.js` draws the hero's wallpaper as a 3D field of pixel blocks with three.js. `main.js` loads it only when WebGL works and the visitor allows motion; otherwise a flat grid shows instead.
- `build.mjs` copies `public/`, the README screenshots, and the app icon into `dist/`, so the site always shows the same images as the README. It also bundles `client/hero3d.js` with esbuild, which keeps only the parts of three.js it uses (about 135 KB gzipped).
- `src/worker.js` serves `dist/` and adds two routes that read the latest release's appcast:
  - `/download` redirects to the newest DMG, or to the Releases page if the appcast can't be read.
  - `/latest.json` returns `{ "version", "dmg" }` for the page.

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
