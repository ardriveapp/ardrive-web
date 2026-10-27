#!/usr/bin/env python3
"""Builds assets/arns/nothing_published.html, the page a removed main name
points at (docs/NAMES.md). Everything is inlined: the logo and Wavehaus,
subset to the page's own characters, so the page makes no requests and stays
well under Turbo's free size. Needs fonttools and brotli.

    python3 tool/arns/build_nothing_published.py
"""
import base64
import json
import io
import pathlib

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
FONTS = ROOT / 'packages/ardrive_ui/assets/fonts'
BRAND = ROOT / 'assets/images/brand'
OUT = ROOT / 'assets/arns/nothing_published.html'

TITLE = 'Nothing here right now'
# Opened at a name, the page names it: "The owner of acme.ar.io has ...".
# Opened by its transaction ID there is no name to show, so it says "The
# owner has ...". Never "this address": to ArDrive users an address is a
# wallet's.
BODY = 'The owner has taken down or moved what was here.'
BODY_AT_NAME = ('The owner of ', ' has taken down or moved what was here.')
HINT = 'If someone sent you this link, ask them for the new one.'
OWNER = 'Own this name?'
OWNER_ACTION = 'Manage it in ArDrive'
OWNER_URL = 'https://app.ardrive.io'
ARDRIVE_URL = 'https://ardrive.io'
# Characters a hostname can add to the body text.
HOST_CHARS = 'abcdefghijklmnopqrstuvwxyz0123456789.-_'


def woff2(name, text):
    font = TTFont(FONTS / name)
    options = subset.Options()
    options.flavor = 'woff2'
    options.layout_features = ['kern', 'liga']
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    buf = io.BytesIO()
    font.flavor = 'woff2'
    font.save(buf)
    return base64.b64encode(buf.getvalue()).decode()


def png(name):
    return base64.b64encode((BRAND / name).read_bytes()).decode()


semibold = woff2('Wavehaus-95SemiBold.otf', TITLE + OWNER_ACTION)
book = woff2('Wavehaus-66Book.otf', BODY + ''.join(BODY_AT_NAME) + HINT + OWNER + HOST_CHARS)

html = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="robots" content="noindex">
<title>{TITLE}</title>
<style>
@font-face {{ font-family: "Wavehaus"; font-weight: 600; src: url(data:font/woff2;base64,{semibold}) format("woff2"); }}
@font-face {{ font-family: "Wavehaus"; font-weight: 400; src: url(data:font/woff2;base64,{book}) format("woff2"); }}
:root {{ --bg: #fafafa; --fg: #121212; --muted: #5c5c5c; --line: #e3e3e3; --red: #d31721; --red-hover: #b8141d; }}
@media (prefers-color-scheme: dark) {{
  :root {{ --bg: #121212; --fg: #fafafa; --muted: #a3a3a3; --line: #2b2b2b; --red-hover: #fe0230; }}
}}
* {{ box-sizing: border-box; }}
html, body {{ margin: 0; min-height: 100%; }}
body {{
  min-height: 100vh; min-height: 100dvh; display: grid; place-items: center;
  padding: 48px 24px; background: var(--bg); color: var(--fg);
  font: 400 16px/1.5 "Wavehaus", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  -webkit-font-smoothing: antialiased; text-align: center;
}}
main {{ display: flex; flex-direction: column; align-items: center; max-width: 440px; }}
.logo {{ display: block; margin-bottom: 48px; }}
.logo img {{ height: 28px; width: auto; display: block; }}
h1 {{ margin: 0; font-weight: 600; font-size: clamp(28px, 6vw, 40px); line-height: 1.15; letter-spacing: -0.01em; text-wrap: balance; }}
p {{ margin: 16px 0 0; color: var(--muted); font-size: 17px; text-wrap: balance; }}
p strong {{ color: var(--fg); font-weight: 400; display: inline-block; max-width: 100%; overflow-wrap: anywhere; }}
.owner {{ margin-top: 48px; padding-top: 24px; border-top: 1px solid var(--line); font-size: 14px; }}
.owner a {{ color: var(--fg); font-weight: 600; text-decoration: none; border-bottom: 1px solid var(--red); }}
.owner a:hover {{ color: var(--red-hover); }}
a:focus-visible {{ outline: 2px solid var(--fg); outline-offset: 3px; border-radius: 2px; }}
</style>
</head>
<body>
<main>
  <a class="logo" href="{ARDRIVE_URL}" rel="noopener" aria-label="ArDrive">
    <picture>
      <source srcset="data:image/png;base64,{png('white_logo_2x.png')}" media="(prefers-color-scheme: dark)">
      <img src="data:image/png;base64,{png('black_logo_2x.png')}" alt="ArDrive" width="124" height="28">
    </picture>
  </a>
  <h1>{TITLE}</h1>
  <p id="what">{BODY}</p>
  <p>{HINT}</p>
  <p class="owner">{OWNER} <a href="{OWNER_URL}" rel="noopener">{OWNER_ACTION}</a></p>
</main>
<script>
  // At a name the page is served from the name's own host (acme.ar.io);
  // opened by its transaction ID it is on a gateway's sandbox subdomain.
  (function () {{
  var host = location.hostname;
  if (location.pathname === '/' && host.indexOf('.') > 0 && !/^[a-z2-7]{{52}}\\./.test(host)) {{
    var what = document.getElementById('what');
    var shown = document.createElement('strong');
    shown.textContent = host;
    what.textContent = '';
    what.append({json.dumps(BODY_AT_NAME[0])}, shown, {json.dumps(BODY_AT_NAME[1])});
  }}
  }})();
</script>
</body>
</html>
'''

OUT.write_text(html)
print(f'{OUT.relative_to(ROOT)}: {len(html.encode())} bytes')
