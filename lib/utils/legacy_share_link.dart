import 'package:ardrive/utils/shared_file_link.dart';

// Legacy shared file links - `https://app.ardrive.io/#/file/{fileId}/view` -
// are permanent. They must resolve under either URL strategy, forever
// (`docs/FILE_SHARING_REDESIGN_PLAN.md` §4.1).
//
// Two things read this file:
//
// 1. `AppRouteInformationParser`, which under path routing is handed the whole
//    legacy route inside the fragment (the host only ever saw `/`) and has to
//    make sense of it;
// 2. the boot shim in `web/index.html`, which runs before Flutter loads and
//    rewrites the address bar with `history.replaceState` so the URL the
//    recipient keeps is the canonical one. `replaceState` performs no network
//    request, so the key never leaves the browser during the migration.
//
// (2) is JavaScript and cannot import this, so it is a transliteration of
// [rewriteLegacyShareLink]. `test/utils/app_url_strategy_test.dart` pins the
// two together by reading `web/index.html` and checking that the shipped
// script still carries [legacyShareLinkPattern] and the pieces below.

/// The route a legacy shared file link is written on, as a pattern over the
/// fragment of a hash-routed URL (the leading `#` removed).
///
/// Group 1 is the file id; group 2 is the pseudo query, if there is one.
///
/// Deliberately narrow: a drive link (`/drives/{driveId}?...`) must not match,
/// this cycle leaves those on the hash route untouched.
const legacyShareLinkPattern = r'^/file/([^/?#]+)/view(?:\?(.*))?$';

/// Rewrites a legacy shared file route onto the canonical `/share` route.
///
/// [hashRoute] is a hash-routed location with no leading `#`, exactly what
/// `window.location.hash.substring(1)` gives the boot shim. Returns `null`
/// when it is not a legacy shared file route, which is the signal to leave the
/// URL alone.
///
/// Both key parameters are lifted out of the query and rewritten as a `#k=`
/// fragment, in the precedence order of §4.2 (`k` beats `fileKey`) - a path
/// route's query is sent to the server, so that is the one move this rewrite
/// must never get wrong. Every other parameter is carried across verbatim,
/// with its original percent-encoding intact.
String? rewriteLegacyShareLink(String hashRoute) {
  final match = _legacyShareLink.firstMatch(hashRoute);

  if (match == null) {
    return null;
  }

  final fileId = match.group(1)!;
  final query = match.group(2) ?? '';

  String? key;
  String? legacyKey;
  final kept = <String>[];

  for (final pair in query.split('&')) {
    if (pair.isEmpty) {
      continue;
    }

    final separator = pair.indexOf('=');
    final name = separator < 0 ? pair : pair.substring(0, separator);
    final value = separator < 0 ? '' : pair.substring(separator + 1);

    if (name == SharedFileLinkParams.key) {
      // An empty parameter is an absent key, not a mangled one - and either
      // way it must not travel on into the query.
      key ??= value.isEmpty ? null : value;
    } else if (name == SharedFileLinkParams.legacyKey) {
      legacyKey ??= value.isEmpty ? null : value;
    } else {
      kept.add(pair);
    }
  }

  // A key that is damaged is still moved: the page needs to be able to say the
  // link arrived damaged rather than silently asking for a key.
  final resolvedKey = key ?? legacyKey;

  final location = StringBuffer(SharedFileLinkRoute.share.pathFor(fileId));

  if (kept.isNotEmpty) {
    location.write('?${kept.join('&')}');
  }

  if (resolvedKey != null) {
    location.write('#${SharedFileLinkParams.key}=$resolvedKey');
  }

  return location.toString();
}

/// Resolves a location whose whole route lives in the fragment.
///
/// Under path routing the host only ever sees `/`, so a legacy link reaches
/// the router as `/#/file/{fileId}/view?fileKey=...` - `PathUrlStrategy` with
/// `includeHash` hands the fragment over verbatim. This turns that back into
/// the route it names, so that legacy shared file links *and* the drive links
/// this cycle leaves alone keep resolving.
///
/// A no-op for every location the hash strategy produces: there the router's
/// location is already everything after the first `#`, so anything left in the
/// fragment is a real fragment (`#k=...`) and never a route.
String normalizeHashRouteLocation(String location) {
  final hashIndex = location.indexOf('#');

  if (hashIndex < 0) {
    return location;
  }

  final beforeHash = location.substring(0, hashIndex);

  // Anything with a path in front of the `#` is already the route; what
  // follows is its fragment.
  if (beforeHash.isNotEmpty && beforeHash != '/') {
    return location;
  }

  final fragment = location.substring(hashIndex + 1);

  // `/#k=...` is a fragment on the root, not a route.
  if (!fragment.startsWith('/')) {
    return location;
  }

  return rewriteLegacyShareLink(fragment) ?? fragment;
}

final _legacyShareLink = RegExp(legacyShareLinkPattern);
