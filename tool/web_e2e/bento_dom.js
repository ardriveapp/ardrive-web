// Checks the signed-out landing's bento on a phone, on the HTML renderer that
// phones get: with the cost tile on screen, its dotted leaders must not be DOM
// elements, and an animation frame must not rebuild the bento's DOM.
//
// Each leader dot drawn into a picture that holds text became a <draw-circle>
// in a div of its own, clipped by an SVG clip path: about 1,100 nodes for the
// three leaders, rebuilt on every frame the bento animated. Phones stalled
// until the browser reloaded the tab. See docs/WEB_E2E_TESTING.md.
//
//   APP_URL=https://staging.ardrive.io/ node bento_dom.js
//
// Needs no wallet and no launch.js: it starts its own headless browser.
// Exits 0 when the bento is cheap, 1 when it isn't, 2 when it couldn't check.
const { chromium, devices } = require('playwright-core');
const { APP_URL, chromePath } = require('./config');

/// More DOM nodes added per frame than this is a repaint of the whole bento.
/// With the fix a frame adds about 20; without it, about 1,250.
const MAX_NODES_PER_FRAME = 200;
const SAMPLE_MS = 5000;

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: chromePath(),
    args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
  });
  try {
    const ctx = await browser.newContext({ ...devices['Pixel 7'] });
    await ctx.addInitScript(() => {
      // The renderer phones get, whatever this machine looks like.
      window.flutterWebRenderer = 'html';
      // Every node added anywhere, shadow roots included, and every frame.
      window.__added = 0;
      window.__frames = 0;
      const observe = (root) => new MutationObserver((records) => {
        for (const r of records) {
          for (const n of r.addedNodes) {
            window.__added += 1 + (n.querySelectorAll ? n.querySelectorAll('*').length : 0);
          }
        }
      }).observe(root, { childList: true, subtree: true });
      observe(document);
      const attachShadow = Element.prototype.attachShadow;
      Element.prototype.attachShadow = function (init) {
        const root = attachShadow.call(this, init);
        observe(root);
        return root;
      };
      const tick = () => { window.__frames++; requestAnimationFrame(tick); };
      requestAnimationFrame(tick);
    });
    const page = await ctx.newPage();
    await page.goto(APP_URL, { waitUntil: 'load', timeout: 120000 });
    await page.waitForFunction(() => location.hash.includes('sign-in'), null, { timeout: 120000 });
    await page.waitForTimeout(8000);

    // To the bottom of the page, where the cost tile is.
    const vp = page.viewportSize();
    await page.mouse.move(vp.width / 2, vp.height / 2);
    for (let i = 0; i < 12; i++) {
      await page.mouse.wheel(0, 600);
      await page.waitForTimeout(400);
    }
    await page.waitForTimeout(2000);

    // The HTML renderer leaves out of the DOM what is off screen, so the
    // bill's text in the DOM means the cost tile is on screen. Some of its
    // text can go to a canvas instead; any one line is enough.
    const BILL = ['What it costs', '1 GB, saved for good', 'Subscription', 'To try it', 'See prices'];
    const inDom = () => page.evaluate((bill) => {
      let circles = 0;
      let nodes = 0;
      let costTile = false;
      const walk = (root) => {
        for (const el of root.querySelectorAll('*')) {
          nodes++;
          if (el.tagName === 'DRAW-CIRCLE') circles++;
          if (el.tagName === 'FLT-PARAGRAPH' && bill.includes(el.textContent)) costTile = true;
          if (el.shadowRoot) walk(el.shadowRoot);
        }
      };
      walk(document);
      return { circles, nodes, costTile };
    }, BILL);

    const before = await inDom();
    if (!before.costTile) {
      console.log('COULD NOT CHECK: the cost tile is not on screen (is APP_URL the signed-out landing?)');
      process.exitCode = 2;
      return;
    }
    if (await page.evaluate(() => !!window.flutterCanvasKit)) {
      console.log('COULD NOT CHECK: the app did not use the HTML renderer');
      process.exitCode = 2;
      return;
    }

    await page.evaluate(() => { window.__added = 0; window.__frames = 0; });
    await page.waitForTimeout(SAMPLE_MS);
    const { added, frames } = await page.evaluate(() => ({ added: window.__added, frames: window.__frames }));
    const after = await inDom();
    const perFrame = Math.round(added / Math.max(1, frames));

    const result = {
      leaderDomDots: after.circles,
      nodesAddedPerFrame: perFrame,
      frames,
      liveDomNodes: after.nodes,
    };
    const ok = after.circles === 0 && perFrame <= MAX_NODES_PER_FRAME && frames > 0;
    console.log(JSON.stringify(result));
    console.log(ok
      ? 'PASS: the bento is cheap on the HTML renderer'
      : `FAIL: ${after.circles} leader dots are DOM elements, ${perFrame} nodes added per frame (at most ${MAX_NODES_PER_FRAME}), ${frames} frames`);
    process.exitCode = ok ? 0 : 1;
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error('COULD NOT CHECK:', e.message);
  process.exitCode = 2;
});
