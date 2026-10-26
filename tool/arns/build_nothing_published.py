#!/usr/bin/env python3
"""Builds assets/arns/nothing_published.html, the page a removed main name
points at (docs/NAMES.md). Everything is inlined: the logo and Wavehaus,
subset to the page's own characters, so the page makes no requests and stays
well under Turbo's free size. Needs fonttools and brotli.

    python3 tool/arns/build_nothing_published.py
"""
import base64
import io
import pathlib

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
FONTS = ROOT / 'packages/ardrive_ui/assets/fonts'
BRAND = ROOT / 'assets/images/brand'
OUT = ROOT / 'assets/arns/nothing_published.html'

TITLE = 'Nothing published here'
BODY = 'This address isn\u2019t showing anything right now.'
ACTION = 'Publish with ArDrive'
ACTION_URL = 'https://ardrive.io'


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


semibold = woff2('Wavehaus-95SemiBold.otf', TITLE + ACTION)
book = woff2('Wavehaus-66Book.otf', BODY)

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
.logo {{ display: block; height: 36px; width: auto; margin-bottom: 56px; }}
.logo img {{ height: 36px; width: auto; display: block; }}
h1 {{ margin: 0; font-weight: 600; font-size: clamp(28px, 6vw, 40px); line-height: 1.15; letter-spacing: -0.01em; text-wrap: balance; }}
p {{ margin: 16px 0 0; color: var(--muted); font-size: 17px; text-wrap: balance; }}
.action {{
  margin-top: 40px; display: inline-flex; align-items: center; justify-content: center;
  height: 48px; padding: 0 24px; border-radius: 8px; background: var(--red); color: #fafafa;
  font-weight: 600; font-size: 16px; text-decoration: none; transition: background-color .15s ease;
}}
.action:hover {{ background: var(--red-hover); }}
.action:focus-visible {{ outline: 2px solid var(--fg); outline-offset: 3px; }}
</style>
</head>
<body>
<main>
  <a class="logo" href="{ACTION_URL}" rel="noopener" aria-label="ArDrive">
    <picture>
      <source srcset="data:image/png;base64,{png('white_logo_2x.png')}" media="(prefers-color-scheme: dark)">
      <img src="data:image/png;base64,{png('black_logo_2x.png')}" alt="ArDrive" width="159" height="36">
    </picture>
  </a>
  <h1>{TITLE}</h1>
  <p>{BODY}</p>
  <a class="action" href="{ACTION_URL}" rel="noopener">{ACTION}</a>
</main>
</body>
</html>
'''

OUT.write_text(html)
print(f'{OUT.relative_to(ROOT)}: {len(html.encode())} bytes')
