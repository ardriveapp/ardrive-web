// Prints the test wallet's AR balance, to compare before and after a run.
//
//   node balance.js
//
// The address is ARDRIVE_E2E_ADDRESS in the credentials file (it's public).
// Asks turbo-gateway.com first, then arweave.net, which rate-limits some
// connections.
const { address, CREDENTIALS } = require('./config');

(async () => {
  const addr = address();
  if (!addr) {
    console.error(`Set ARDRIVE_E2E_ADDRESS in ${CREDENTIALS} (see docs/WEB_E2E_TESTING.md)`);
    process.exit(2);
  }
  for (const gateway of ['https://turbo-gateway.com', 'https://arweave.net']) {
    try {
      const r = await fetch(`${gateway}/wallet/${addr}/balance`, { signal: AbortSignal.timeout(20000) });
      const text = (await r.text()).trim();
      if (r.ok && /^\d+$/.test(text)) {
        console.log(`${text} winston (${(Number(text) / 1e12).toFixed(4)} AR) from ${gateway}`);
        return;
      }
      console.error(`${gateway}: ${r.status} ${text.slice(0, 60)}`);
    } catch (e) {
      console.error(`${gateway}: ${e.message}`);
    }
  }
  process.exit(1);
})();
