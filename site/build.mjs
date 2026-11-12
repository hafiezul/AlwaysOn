// Assembles dist/ from public/ plus the app icon, so the site's favicon is
// always the app's own. It also bundles the page script with the parts of
// three.js it uses. The page's screenshots are upscaled copies kept in
// public/images/ (see README.md).
//
// With --watch it keeps going: it rebundles when anything under client/
// changes and copies files from public/ as they're saved, so `wrangler dev
// --live-reload` (see `npm run dev`) reloads the page.
import { cpSync, existsSync, mkdirSync, rmSync, watch } from "node:fs";
import { context } from "esbuild";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..");
const dist = join(here, "dist");
const icons = join(repo, "AlwaysOn/Resources/Assets.xcassets/AppIcon.appiconset");
const watching = process.argv.includes("--watch");

// A watch run starts after a full build (npm run dev), so it leaves dist/ in
// place for the dev server that is starting up beside it
if (!watching) rmSync(dist, { recursive: true, force: true });
mkdirSync(join(dist, "images"), { recursive: true });

cpSync(join(here, "public"), dist, { recursive: true });
cpSync(join(icons, "icon_32x32@2x.png"), join(dist, "images/icon-64.png"));
cpSync(join(icons, "icon_128x128@2x.png"), join(dist, "images/icon-256.png"));
cpSync(join(icons, "icon_512x512.png"), join(dist, "images/icon-512.png"));

const bundle = (entry, outfile) =>
  context({
    entryPoints: [join(here, entry)],
    outfile: join(dist, outfile),
    bundle: true,
    format: "esm",
    minify: !watching,
    sourcemap: watching ? "inline" : false,
    target: "es2020",
    legalComments: "eof",
    logLevel: watching ? "info" : "warning",
  });

// The page's script, with GSAP, Lenis, and the parts of three.js the avatar uses
const bundles = [await bundle("client/main.js", "main.js")];

if (!watching) {
  await Promise.all(bundles.map((ctx) => ctx.rebuild()));
  await Promise.all(bundles.map((ctx) => ctx.dispose()));
  console.log("Built site into dist/");
} else {
  await Promise.all(bundles.map((ctx) => ctx.watch()));

  // Copy each saved file from public/ into dist/, and remove deleted ones
  const publicDir = join(here, "public");
  watch(publicDir, { recursive: true }, (_event, name) => {
    // Skip editors' temporary files; they're renamed over the real file a moment later
    if (!name || /\.tmp\.|\.swp$|~$/.test(name)) return;
    const from = join(publicDir, name);
    const to = join(dist, name);
    try {
      if (existsSync(from)) cpSync(from, to, { recursive: true });
      else rmSync(to, { recursive: true, force: true });
      console.log(`Copied public/${name}`);
    } catch (error) {
      console.error(`Couldn't copy public/${name}: ${error.message}`);
    }
  });
  console.log("Built site into dist/, watching client/ and public/ for changes");
}
