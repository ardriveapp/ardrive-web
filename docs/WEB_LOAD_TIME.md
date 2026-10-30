# Web load time

How the web app gets from a blank tab to a usable sign-in panel, and the rules
that keep it fast. The numbers and the reasons behind each rule are in the
pull request that introduced this file.

## The start, in order

1. **index.html.** The splash (logo, progress bar) draws at once, in the theme
   the app will open in. `main.dart.js` is preloaded; the deferred scripts
   (pdf.js, ario_sdk, pica) and ethers load beside it.
2. **`load`.** flutter.js runs `main.dart.js`, the engine starts (CanvasKit on
   desktop browsers, the HTML renderer on phones), then `main()`.
3. **Before `runApp`.** Local storage, then the config
   (`ConfigFetcher.fetchConfig`, which on a first visit may ask the serving
   host's parent domain whether it is an AR.IO gateway). Only those two are
   awaited. Beside them the database starts opening, the panel's logo starts
   loading, and the app version (version.json) loads.
4. **First frame.** For a start without a link, the sign-in page, once the
   address has been read. Its panel is the one the last start found
   (`ProfilePresenceHint`): Welcome back, the landing, or a plain card when
   there is no telling. It is drawn, not yet usable, and nothing on the page
   moves. The bento waits too: a plain surface in its place on a desktop,
   nothing on a phone. Every frame is drawn on the main thread, which the
   database's worker needs while it opens; drawn on the first frame, the
   bento alone cost a throttled phone about 6 s of it.
5. **The database.** Opening it (the OPFS worker, or IndexedDB) and creating
   or migrating the schema is most of what is left. When `LoginBloc` has its
   answer the panel becomes usable, the page starts moving, and the log says
   `login: panel ready`.
6. **After the panel.** The bento draws and loads its pictures. A start with
   no account clears what an earlier visitor left. The pictures for later
   steps load a second later, one a frame.

A link (a drive, a shared file, a raw transaction) keeps the splash until the
check is in, because for a visitor it ends somewhere other than sign-in.

## Rules

- **Build with `--dart2js-optimization=O2`.** O2 is O1 plus minification and
  keeps every type check; O3 and O4 drop them. Minified, a class's name is not
  its source name: never compare `runtimeType.toString()`, `Type.toString()`
  or an object's default `toString()` against a string, or use one as a key
  that must survive a release. Compare types (`is`, `==` on `Type`), or give
  the class an explicit name. Log lines that print `runtimeType` read
  `minified:Xy` in release builds.
- **Nothing heavy before the first frame.** Anything awaited before `runApp`
  delays every start. Load what only later screens read after the first
  frame, as the app version is.
- **Don't parse SVGs ahead of the first paint.** flutter_svg parses on the
  main thread on the web. `preCacheLaterLoginAssets` runs once the panel is
  up; keep its lists to pictures a screen still shows.
- **The panel waits for the database, the page doesn't.** A view drawn before
  the check is in takes `ready: false` and sends nothing until it is
  `true`. A returning user must never see the landing: with no hint, draw the
  plain card.
- **Nothing heavy before the panel is usable.** The sign-in page sets
  `TickerMode` off until then; the bento (`_Bento` in login_page.dart) and its
  timers (`_still` in tiles_view.dart) follow it. Anything new on that page
  must do the same, or it costs the database open its main-thread time.

## Measuring

Measure a release build, not `flutter run`: DDC is several times slower. Serve
it with and without gzip (Firebase compresses; an AR.IO gateway serving the
un-encoded deploy does not), and load it in headless Chromium from a fresh
profile, on a desktop viewport and on a phone profile (Android user agent,
4x CPU slowdown, 9 Mbps down / 165 ms RTT). Mark `main.dart.js`'s
`responseEnd`, the `flutter-first-frame` event, the first screencast frame
that shows the panel, and the `login: panel ready` log line. Take the median
of several runs: the timings move by a second or more from run to run.
