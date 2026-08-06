/**
 * PDF.js configuration for the `pdfx` Flutter plugin.
 *
 * `pdfx` ships a `pdfx:install_web` script that writes CDN `<script>` tags into
 * `web/index.html` (jsdelivr, pdfjs-dist@2.12.313). That script is deliberately
 * NOT used here. This app is deployed to Arweave, where a build is permanent
 * and immutable: a CDN dependency baked into it could never be patched, and it
 * breaks under the strict CSP an AR.IO gateway serves. Every byte pdf.js needs
 * is vendored beside this file instead.
 *
 * Vendored from pdfjs-dist 2.12.313 (the exact version `pdfx` 2.6.0 targets):
 *   pdf.min.js         build/pdf.min.js
 *   pdf.worker.min.js  build/pdf.worker.min.js
 *
 * The `cmaps/` directory is deliberately NOT vendored. Its 168 .bcmap files are
 * 1.3 MB, and this build ships to Arweave where every byte is permanent. They
 * are only consulted by PDFs that use a *predefined* CJK character encoding -
 * typically older documents; anything with embedded fonts, which is the modern
 * norm, never touches them. Such a PDF now renders with missing glyphs instead
 * of failing. Restore the directory and the `cMapUrl`/`cMapPacked` options
 * below if that trade stops being worth 1.3 MB.
 *
 * Both URLs below are resolved against *this file's* own URL rather than the
 * document's, so they keep working when the app is served from a subpath - an
 * AR.IO gateway serving a manifest under `/{txid}/`, for instance - where a
 * root-absolute `/js/...` would miss.
 */
(function () {
  'use strict';

  var here = document.currentScript && document.currentScript.src;
  var base = here ? new URL('.', here).href : 'js/pdfjs/';

  if (typeof pdfjsLib === 'undefined') {
    console.error('[pdfjs] pdf.min.js did not load; PDF previews will fall back');
    return;
  }

  pdfjsLib.GlobalWorkerOptions.workerSrc = base + 'pdf.worker.min.js';

  // Read by `pdfx` on every `getDocument` call
  // (pdfx/lib/src/renderer/web/pdfjs.dart). `params` is merged in as-is, and is
  // where any future pdf.js option belongs.
  //
  // Note what is *not* here: `enableScripting`. pdf.js defaults it to false, so
  // JavaScript embedded in a PDF never executes, and pages only ever become
  // canvas pixels handed back to Flutter as an image - never DOM on this
  // origin. See `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3.
  // No `cMapUrl`: the cmaps are not vendored (see above), and pointing pdf.js
  // at a directory that is not there would make it fetch 404s per glyph rather
  // than skip them.
  window.pdfRenderOptions = {};

  // SECURITY: pdf.js 2.12.313 is vulnerable to CVE-2024-4367. It compiles
  // Type1 glyph paths with `new Function(...)` when `isEvalSupported` is true,
  // and does not type-check the FontMatrix those arguments come from - so a
  // crafted PDF executes arbitrary JavaScript on this origin. That is the
  // origin holding a recipient's access key in sessionStorage, and PDFs here
  // are attacker-chosen: `/view/{txId}` renders any transaction's bytes.
  //
  // The fix is applied by patching `isEvalSupported`'s default to `false`
  // directly in the vendored `pdf.min.js` (search it for `isEvalSupported=!1`).
  // It is NOT set here, because pdfx 2.6.0 merges this object's `params` into
  // getDocument with `Map.addAll` over a raw JS object
  // (pdfx/lib/src/renderer/web/pdfjs.dart:47-51), which throws under dart2js -
  // securing it that way would break PDF rendering outright.
  //
  // Patching a vendored minified file is a maintenance hazard, so: when this
  // build is replaced, re-apply the patch or move to pdf.js >= 4.2.67, which
  // fixes the CVE upstream and needs a Flutter newer than the pinned 3.19.6
  // before pdfx can target it.
})();
