import 'package:ardrive/utils/shared_file_link.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

/// How this build represents its routes in the browser's URL.
///
/// See `docs/FILE_SHARING_REDESIGN_PLAN.md` §1.1 for the route table and §4.1
/// for the migration.
enum AppUrlStrategy {
  /// Everything the router reads lives after a `#`:
  /// `https://app.ardrive.io/#/file/{fileId}/view?fileKey=...`.
  ///
  /// The browser never sends a fragment to a server, so every route the app
  /// invents costs the host nothing: every request is `GET /`. That is why
  /// this is the only strategy that works on a host with no rewrite rules -
  /// which is every host ArDrive is served from today.
  hash,

  /// The route *is* the path: `https://app.ardrive.io/share/{fileId}#k=...`.
  ///
  /// Requires the host to answer `/share/*` and `/view/*` with `index.html`.
  /// Without that, a direct visit or a refresh is a 404 rather than a page.
  path;

  /// The route shape newly built shared file links use.
  ///
  /// Both shapes are *parsed* under either strategy, forever; this only picks
  /// the one a new link is written on.
  SharedFileLinkRoute get sharedFileRoute => this == AppUrlStrategy.path
      ? SharedFileLinkRoute.share
      : SharedFileLinkRoute.legacy;

  /// Where a newly built link puts the file key.
  ///
  /// On the hash route the whole query already sits after the `#`, so the key
  /// is client-side wherever it goes and the URL's one fragment is spent. On a
  /// path route the query is sent to the server, so the fragment is the only
  /// position a key may ever occupy (§1.2, §4.2).
  SharedFileLinkKeyPlacement get fileKeyPlacement =>
      this == AppUrlStrategy.path
          ? SharedFileLinkKeyPlacement.fragment
          : SharedFileLinkKeyPlacement.hashQuery;

  /// What a route location is prefixed with to become a link on an origin.
  String get linkPrefix => this == AppUrlStrategy.path ? '' : '/#';
}

/// The URL strategy this build runs on.
///
/// **Defaults to [AppUrlStrategy.hash] - today's behavior, unchanged.**
///
/// ---
///
/// ## Do not flip this until the hosting work has landed
///
/// Path routing means the browser asks the host for `/share/{fileId}` and
/// `/view/{txId}` as real paths. Nothing serves those paths today, so flipping
/// this without the rewrites turns every direct visit and every page refresh
/// into a 404. The capability is built and tested; switching it on is a
/// hosting decision, not a code one.
///
/// What has to exist first:
///
/// 1. **SPA rewrites on the app host** - `/share/*` and `/view/*` (and any
///    other app path) answered with `index.html`, status 200.
/// 2. **A gateway-served equivalent** - the Arweave path manifest the app is
///    deployed as needs a `fallback` to the `index.html` data item so an AR.IO
///    gateway answers unknown paths with the app instead of 404 (manifest
///    version `0.2.0`, `deploy/`).
/// 3. **A `<base href="/">` element in `web/index.html`** - `PathUrlStrategy`
///    throws at startup without one. Note what that costs: with a base href of
///    `/`, the build no longer works when served from a sub-path such as
///    `https://arweave.net/{manifestTxId}/`, only from an origin root
///    (`https://app.ardrive.io/`, an ArNS subdomain, a sandbox subdomain).
/// 4. **A referrer policy in `web/index.html`** - `<meta name="referrer"
///    content="strict-origin">`, already there and asserted by
///    `test/utils/app_url_strategy_test.dart`. A hash route is never sent in a
///    `Referer` header, so it costs nothing today; a *path* route is the whole
///    link - `/share/{fileId}?d=...` - and without this every subresource
///    request the page makes carries it to the gateway it fetches from and to
///    anything else the page talks to. The payload being packed does not make
///    this optional: base64url is an encoding, not a secret, and `n` and `ct`
///    are private-file secrets (§1.2). It only means the leak needs one decode
///    step rather than none.
///
/// ## Enabling it, once those exist
///
/// 1. `kAppUrlStrategy` here -> [AppUrlStrategy.path].
/// 2. `window.ardriveUsePathUrlStrategy` in `web/index.html` -> `true`, which
///    arms the legacy-link boot shim (§4.1). The two are pinned together by
///    `test/utils/app_url_strategy_test.dart`, which fails if only one moves.
///
/// Nothing else changes: every route parses under both strategies, and legacy
/// `/#/file/{fileId}/view?fileKey=...` links keep resolving forever either way.
const kAppUrlStrategy = AppUrlStrategy.hash;

/// Installs [strategy] with the engine. Call once, before `runApp`.
///
/// A no-op off the web, where [setUrlStrategy] is itself a no-op.
void configureAppUrlStrategy([AppUrlStrategy strategy = kAppUrlStrategy]) {
  if (strategy != AppUrlStrategy.path) {
    // Hash routing is the engine's own default. Installing it explicitly would
    // change nothing and could only introduce a difference where there is none.
    return;
  }

  // `PathUrlStrategy(..., includeHash: true)` rather than the one-liner
  // `usePathUrlStrategy()`, which leaves `includeHash` false. Two things break
  // without the hash:
  //
  // - `#k=` never reaches the route parser, and the fragment is the only place
  //   a file key may travel on a path route (§1.2);
  // - every legacy `/#/file/{fileId}/view` link looks to the router like a bare
  //   `/`, so links that must work forever would resolve to nothing (§4.1).
  setUrlStrategy(PathUrlStrategy(BrowserPlatformLocation(), true));
}
