#!/usr/bin/env python3
"""Writes the Sparkle appcast for one release.

The appcast ships as a release asset, so the app's feed URL
(releases/latest/download/appcast.xml) always resolves to the newest release.

  Scripts/make-appcast.py --version 1.8.0 --build 240 \\
      --dmg artifacts/AlwaysOn-v1.8.0.dmg --ed-signature <sig> \\
      --download-url https://github.com/.../AlwaysOn-v1.8.0.dmg \\
      --release-url https://github.com/.../releases/tag/v1.8.0 \\
      --notes-html notes.html --minimum-system-version 13.0 \\
      --output artifacts/appcast.xml
"""

import argparse
import os
import sys
from email.utils import formatdate
from xml.sax.saxutils import escape, quoteattr

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def cdata(text: str) -> str:
    # "]]>" would end the section early; split it across two sections
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", required=True, help="marketing version, e.g. 1.8.0")
    parser.add_argument("--build", required=True, help="CFBundleVersion Sparkle compares against")
    parser.add_argument("--dmg", required=True, help="path to the signed DMG")
    parser.add_argument("--ed-signature", required=True, help="EdDSA signature from sign_update")
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--release-url", required=True)
    parser.add_argument("--notes-html", help="file with the release notes as HTML")
    parser.add_argument("--minimum-system-version", default="13.0")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    if not args.build.isdigit():
        parser.error(f"--build must be an integer, got {args.build!r}")
    for url in (args.download_url, args.release_url):
        if not url.startswith("https://"):
            parser.error(f"URLs must use https: {url}")

    length = os.path.getsize(args.dmg)
    notes = ""
    if args.notes_html:
        with open(args.notes_html, encoding="utf-8") as handle:
            notes = handle.read().strip()

    description = f"\n      <description>{cdata(notes)}</description>" if notes else ""

    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="{SPARKLE_NS}">
  <channel>
    <title>AlwaysOn</title>
    <link>{escape(args.release_url)}</link>
    <language>en</language>
    <item>
      <title>Version {escape(args.version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <link>{escape(args.release_url)}</link>
      <sparkle:version>{args.build}</sparkle:version>
      <sparkle:shortVersionString>{escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(args.minimum_system_version)}</sparkle:minimumSystemVersion>{description}
      <enclosure url={quoteattr(args.download_url)} length="{length}" type="application/x-apple-diskimage" sparkle:edSignature={quoteattr(args.ed_signature)}/>
    </item>
  </channel>
</rss>
"""
    with open(args.output, "w", encoding="utf-8") as handle:
        handle.write(xml)
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
