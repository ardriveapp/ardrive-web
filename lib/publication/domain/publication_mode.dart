import 'package:flutter/foundation.dart';

/// Whether this page is a publication: ArDrive opened read-only on one drive
/// or folder from a published page manifest (docs/PUBLICATIONS.md).
///
/// A page says so with `<meta name="ardrive-publication" content="publication.json">`
/// in its `index.html`, which the publisher writes into the release's own
/// `index.html`. The app reads it once, in `main()`, before any service
/// starts, because publication mode changes how they start: no stored config, no
/// login, no analytics, no Turbo, no sync, an in-memory database.
///
/// Off the web there is no document, so it is always off.
class PublicationMode {
  PublicationMode._();

  static String? _settingsPath;

  /// Whether the app is running as a publication.
  static bool get isOn => _settingsPath != null;

  /// Where the page's `publication.json` is, relative to the page. Only set when
  /// [isOn].
  static String? get settingsPath => _settingsPath;

  static String? _pageTitle;

  /// The page's own `<title>`, which the publisher wrote, as the page loaded.
  /// Only set when [isOn]. The app names its window with it rather than
  /// "ArDrive": Flutter sets `document.title` from `MaterialApp.title`.
  static String? get pageTitle => _pageTitle;

  /// Reads the page's switch once. [readMetaContent] returns the `content` of
  /// the page's `ardrive-publication` meta tag, or null when there is none;
  /// [readTitle] the document's title.
  static void detect(
    String? Function() readMetaContent, {
    String? Function()? readTitle,
  }) {
    _settingsPath = parsePublicationMetaContent(readMetaContent());
    final title = isOn ? readTitle?.call()?.trim() : null;
    _pageTitle = title == null || title.isEmpty ? null : title;
  }

  @visibleForTesting
  static void debugSet(String? settingsPath) => _settingsPath = settingsPath;
}

/// The settings path a page's meta tag names, or null when the tag is absent
/// or names anything but a plain relative path.
///
/// A publication may only talk to the host serving it, so the settings must
/// sit beside the page: an absolute URL, a scheme, a path from the root or a
/// step up out of the manifest would each read them from somewhere else, and
/// switch publication mode off instead.
@visibleForTesting
String? parsePublicationMetaContent(String? content) {
  final path = content?.trim();
  if (path == null || path.isEmpty) return null;
  if (!isPlainRelativePath(path)) return null;
  return path;
}

/// Whether [path] names a file inside the page's own manifest: no scheme, no
/// host, no leading slash, no `..` or `.` segment, no query or fragment, and
/// nothing but the characters a manifest path uses.
bool isPlainRelativePath(String path) {
  if (path.isEmpty || path.startsWith('/')) return false;
  if (!RegExp(r'^[A-Za-z0-9._\-/]+$').hasMatch(path)) return false;
  final segments = path.split('/');
  return segments.every((s) => s.isNotEmpty && s != '.' && s != '..');
}
