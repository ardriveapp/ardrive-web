// Runs one step against the browser launch.js started, then screenshots it.
//
//   node step.js <name> '<async JS body>'
//
// The body can use: page, wait(ms), shot(name), queueFiles([paths]),
// labels() and clickLabel(text). The screenshot lands in
// $E2E_DIR/shots/<name>.png; read it before the next step.
//
// Flutter draws on a canvas, so most clicks are page.mouse.click(x, y) at
// coordinates read off the last screenshot (the viewport is 1440x900).
// labels() lists the accessibility nodes Flutter exposes, with their centres,
// for the widgets that have one.
const { chromium } = require('playwright-core');
const fs = require('fs');
const { E2E_DIR, CDP_PORT, ensureDirs } = require('./config');

(async () => {
  const [name, body] = process.argv.slice(2);
  if (!name || body === undefined) {
    console.error("usage: node step.js <name> '<async JS body>'");
    process.exit(2);
  }
  ensureDirs();
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`);
  const page = browser.contexts()[0].pages()[0];
  const shot = (n) => page.screenshot({ path: `${E2E_DIR}/shots/${n}.png` });
  const wait = (ms) => page.waitForTimeout(ms);
  const queueFiles = (paths) => fs.writeFileSync(`${E2E_DIR}/nextfiles.json`, JSON.stringify(paths));
  const labels = () => page.evaluate(() => {
    const all = [];
    const walk = (root) => root.querySelectorAll('*').forEach((e) => {
      if (e.tagName === 'FLT-SEMANTICS') all.push(e);
      if (e.shadowRoot) walk(e.shadowRoot);
    });
    walk(document);
    return all.map((e) => {
      const r = e.getBoundingClientRect();
      return {
        label: (e.getAttribute('aria-label') || e.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 70),
        x: Math.round(r.x + r.width / 2),
        y: Math.round(r.y + r.height / 2),
      };
    }).filter((n) => n.label && n.x > 0);
  });
  const clickLabel = async (text) => {
    const hit = (await labels()).find((n) => n.label.includes(text));
    if (!hit) throw new Error(`nothing labelled "${text}"`);
    await page.mouse.click(hit.x, hit.y);
    return hit;
  };
  let failed = false;
  try {
    await eval(`(async () => { ${body} })()`);
  } catch (e) {
    failed = true;
    console.log('STEP ERROR', e.message);
  }
  // Off every control, so the screenshot shows no hover state: a hovered
  // primary button looks like a disabled one.
  await page.mouse.move(1439, 899);
  await page.waitForTimeout(300);
  await shot(name);
  console.log('SHOT', `${E2E_DIR}/shots/${name}.png`);
  process.exit(failed ? 1 : 0);
})();
