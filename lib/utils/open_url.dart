import 'package:ardrive/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// The only URL schemes ArDrive will hand to the platform's launcher.
///
/// `openUrl` is reached from places where the URL is a constant
/// (`Resources.docsLink`), from places where it is assembled from a
/// configured gateway, and - since the generalized transaction viewer - from
/// places where it came off the network. The last kind is why this list exists:
/// `javascript:` runs script in whatever document opens it, `data:` and `blob:`
/// open an attacker-authored document that browsers have historically let
/// inherit an origin, and `file:` reads the machine the app is running on.
/// None of them are ever what a link in this app means.
///
/// `http` is here because the app is developed and tested against local
/// gateways; production URLs are all `https`.
const Set<String> allowedUrlSchemes = {'https', 'http'};

/// Thrown instead of launching, when a URL is not something ArDrive will open.
class UnsupportedUrlSchemeException implements Exception {
  UnsupportedUrlSchemeException(this.url);

  final String url;

  @override
  String toString() =>
      'Refused to open a URL that is not http(s): $url';
}

/// The URL [url] should be launched as, or `null` when it must not be launched
/// at all.
///
/// Exposed so callers can decide *whether* to offer a link without having to
/// try to open it and catch the refusal.
Uri? parseLaunchableUrl(String url) {
  // Leading whitespace and control characters are the classic way to smuggle a
  // scheme past a check that a browser then re-normalises away.
  final trimmed = url.trim();

  if (trimmed.isEmpty || trimmed.codeUnits.any((unit) => unit < 0x20)) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);

  if (uri == null || !uri.hasScheme) {
    return null;
  }

  // `Uri` lower-cases the scheme it parses, so `JaVaScRiPt:` arrives here as
  // `javascript`. The extra `toLowerCase` costs nothing and does not rely on
  // that.
  if (!allowedUrlSchemes.contains(uri.scheme.toLowerCase())) {
    return null;
  }

  // An http(s) URL without a host is not a destination - it is a relative
  // reference that a browser would resolve against whatever page opened it.
  if (uri.host.isEmpty) {
    return null;
  }

  return uri;
}

Future<void> openUrl({
  required String url,
  bool openInWebview = false,
  String? webOnlyWindowName,
}) async {
  final uri = parseLaunchableUrl(url);

  if (uri == null) {
    logger.e('Refused to open a URL that is not http(s): $url');

    throw UnsupportedUrlSchemeException(url);
  }

  final mode = openInWebview
      ? LaunchMode.platformDefault
      : LaunchMode.externalApplication;

  if (await canLaunchUrl(uri)) {
    await launchUrl(
      uri,
      mode: mode,
      webOnlyWindowName: webOnlyWindowName,
    );
  } else {
    throw 'Could not launch $url';
  }
}
