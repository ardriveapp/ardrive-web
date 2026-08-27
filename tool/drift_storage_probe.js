// Reports which drift WasmStorageImplementation this origin would get.
//
// Paste into the DevTools console on the page you want to test. Reproduces the
// decision in drift 2.16's WasmDatabaseOpener.probe() (lib/src/web/wasm_setup.dart
// and wasm_setup/shared.dart) using the same feature checks, in the same worker
// scopes, without needing drift itself.
//
// Tiers, best first: opfsShared, opfsLocks, sharedIndexedDb, unsafeIndexedDb,
// inMemory. Only the two opfs tiers give bounded memory; the indexedDb tiers
// hold the whole database in RAM.
(async () => {
  // Runs inside BOTH a dedicated worker and a shared worker's nested worker.
  const workerProbe = `
    async function checkOpfs() {
      try {
        if (!navigator.storage || !navigator.storage.getDirectory) return false;
        const root = await navigator.storage.getDirectory();
        const fh = await root.getFileHandle('_drift_feature_detection', {create: true});
        const h = await fh.createSyncAccessHandle();
        // Older drafts made getSize() async; drift rejects those browsers.
        const size = h.getSize();
        const ok = typeof size === 'number';
        if (size instanceof Promise) await size;
        h.close();
        await root.removeEntry('_drift_feature_detection').catch(() => {});
        return ok;
      } catch (e) { return false; }
    }
    async function checkIdb() {
      try {
        if (typeof indexedDB === 'undefined') return false;
        await new Promise((res, rej) => {
          const r = indexedDB.open('_drift_feature_detection');
          r.onsuccess = () => { r.result.close(); res(); };
          r.onerror = () => rej(r.error);
        });
        indexedDB.deleteDatabase('_drift_feature_detection');
        return true;
      } catch (e) { return false; }
    }
    async function report() {
      return {
        nestedWorkers: typeof Worker !== 'undefined',
        sharedArrayBuffers: typeof SharedArrayBuffer !== 'undefined',
        opfs: await checkOpfs(),
        indexedDb: await checkIdb(),
      };
    }`;

  const dedicatedSrc = workerProbe +
    `\nreport().then(r => postMessage(r));`;

  // A shared worker cannot touch OPFS itself; drift asks whether it can spawn a
  // dedicated worker that can. That nesting is the Firefox-only part.
  const sharedSrc = `
    onconnect = (e) => {
      const port = e.ports[0];
      (async () => {
        let nested = typeof Worker !== 'undefined';
        let nestedOpfs = false, idb = false;
        try {
          ${workerProbe.replace(/\n/g, '\n          ')}
          idb = await checkIdb();
        } catch (err) { }
        if (nested) {
          try {
            const inner = new Worker(URL.createObjectURL(new Blob([
              ${JSON.stringify(dedicatedSrc)}
            ], {type: 'text/javascript'})));
            nestedOpfs = await new Promise((res) => {
              const t = setTimeout(() => res(false), 5000);
              inner.onmessage = (m) => { clearTimeout(t); res(!!m.data.opfs); };
              inner.onerror = () => { clearTimeout(t); res(false); };
            });
          } catch (err) { nested = false; }
        }
        port.postMessage({nested, nestedOpfs, indexedDb: idb});
      })();
    };`;

  const blobUrl = (src) =>
    URL.createObjectURL(new Blob([src], {type: 'text/javascript'}));

  const runDedicated = () => new Promise((res) => {
    try {
      const w = new Worker(blobUrl(dedicatedSrc));
      const t = setTimeout(() => res(null), 8000);
      w.onmessage = (m) => { clearTimeout(t); w.terminate(); res(m.data); };
      w.onerror = () => { clearTimeout(t); res(null); };
    } catch (e) { res(null); }
  });

  const runShared = () => new Promise((res) => {
    if (typeof SharedWorker === 'undefined') return res(null);
    try {
      const w = new SharedWorker(blobUrl(sharedSrc), 'drift probe');
      const t = setTimeout(() => res(null), 10000);
      w.port.onmessage = (m) => { clearTimeout(t); res(m.data); };
      w.onerror = () => { clearTimeout(t); res(null); };
      w.port.start();
    } catch (e) { res(null); }
  });

  const [dedicated, shared] = await Promise.all([runDedicated(), runShared()]);

  const available = [];
  if (shared && shared.nested && shared.nestedOpfs) available.push('opfsShared');
  if (dedicated && dedicated.nestedWorkers && dedicated.opfs &&
      dedicated.sharedArrayBuffers) available.push('opfsLocks');
  if (shared && shared.indexedDb) available.push('sharedIndexedDb');
  if (dedicated && dedicated.indexedDb) available.push('unsafeIndexedDb');
  available.push('inMemory');

  const chosen = available[0];
  const bounded = chosen === 'opfsShared' || chosen === 'opfsLocks';

  console.log('%c drift storage probe ', 'background:#222;color:#fff');
  console.log('origin                :', location.origin);
  console.log('crossOriginIsolated   :', self.crossOriginIsolated);
  console.log('SharedArrayBuffer     :', typeof SharedArrayBuffer !== 'undefined');
  console.log('dedicated worker      :', dedicated);
  console.log('shared worker         :', shared);
  console.log('available (best first):', available);
  console.log('%cWOULD USE: ' + chosen, 'font-weight:bold;font-size:14px');
  console.log(bounded
    ? 'Bounded memory: YES (OPFS, paged on disk)'
    : 'Bounded memory: NO — the whole database is held in RAM');
  return {origin: location.origin, chosen, bounded, available, dedicated, shared,
          crossOriginIsolated: self.crossOriginIsolated};
})();
