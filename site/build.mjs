// Assembles dist/ from public/ plus the README screenshots and app icon, so
// the site always shows the same images as the README without keeping copies.
// It also bundles the 3D hero with the parts of three.js it uses.
import { cpSync, mkdirSync, rmSync } from "node:fs";
import { build } from "esbuild";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..");
const dist = join(here, "dist");
const icons = join(repo, "AlwaysOn/Resources/Assets.xcassets/AppIcon.appiconset");

rmSync(dist, { recursive: true, force: true });
mkdirSync(join(dist, "images"), { recursive: true });

cpSync(join(here, "public"), dist, { recursive: true });
cpSync(join(repo, "screenshots"), join(dist, "screenshots"), { recursive: true });
cpSync(join(icons, "icon_32x32@2x.png"), join(dist, "images/icon-64.png"));
cpSync(join(icons, "icon_128x128@2x.png"), join(dist, "images/icon-256.png"));
cpSync(join(icons, "icon_512x512.png"), join(dist, "images/icon-512.png"));

await build({
  entryPoints: [join(here, "client/hero3d.js")],
  outfile: join(dist, "hero3d.js"),
  bundle: true,
  format: "esm",
  minify: true,
  target: "es2020",
  legalComments: "eof",
  logLevel: "warning",
});

console.log("Built site into dist/");
