/// The files a publication adds to a release (docs/PUBLICATIONS.md, "What a
/// page is"): `publication.json`, the page's `index.html`, `files.html`,
/// `sitemap.xml` and the manifest, and the tags that make the manifest an
/// ArFS Publication entity.
///
/// A port of `tool/publication/page.mjs`, which stays the reference: for the
/// same inputs both write the same bytes (test/publication/domain/
/// publication_files_test.dart checks it against the tool). Every output is
/// deterministic: fixed key order, sorted maps, two-space JSON with a final
/// newline.
library;

import 'dart:convert';

import 'package:ardrive_utils/ardrive_utils.dart'
    show EntityTag, EntityTypeTag, arfsVersion;

/// The publication.json version this build writes for a drive or folder page.
/// It stays at 1 so the viewers already published can open new ones.
const publicationVersion = 1;

/// The version a file page is written as: only a viewer that knows the file
/// scope can open one, and version 2 says so.
const filePublicationVersion = 2;

/// A transaction tag, as the publisher writes it.
typedef PublicationTag = ({String name, String value});

/// The tags that make a publication's manifest the ArFS entity
/// (docs/ArweaveFS.md, "Publication"). The uploader adds Content-Type, the
/// app tags and Unix-Time. Neither [folderId] nor [fileId] for a whole drive;
/// a file page names its file with `Publication-Scope: file` and `File-Id`.
List<PublicationTag> publicationEntityTags({
  required String driveId,
  required String publicationId,
  String? folderId,
  String? fileId,
}) =>
    [
      (name: EntityTag.arFs, value: arfsVersion),
      (name: EntityTag.entityType, value: EntityTypeTag.publication),
      (name: EntityTag.driveId, value: driveId),
      (name: EntityTag.publicationId, value: publicationId),
      if (fileId != null) ...[
        (name: EntityTag.publicationScope, value: 'file'),
        (name: EntityTag.fileId, value: fileId),
      ] else
        (name: EntityTag.publicationScope, value: folderId ?? 'drive'),
      (
        name: EntityTag.publicationVersion,
        value:
            '${fileId != null ? filePublicationVersion : publicationVersion}',
      ),
    ];

/// The tags of every other file a publication adds: none is an entity.
List<PublicationTag> publicationPartTags(String publicationId) =>
    [(name: EntityTag.publicationId, value: publicationId)];

/// The most files `files.html` and `sitemap.xml` list.
const publicationFilesPageCap = 5000;

String _json(Object value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

Map<String, T> _sorted<T>(Map<String, T> map) => Map.fromEntries(
    map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));

/// `publication.json`. [snapshotTags] are every tag of the artifact, which the
/// viewer builds its import candidate from instead of GraphQL. [fileCount]
/// (what the publication lists, for its owner), [keywords] and [license] are
/// written only when set. [generatedCard] marks `social.jpg` as the card
/// ArDrive drew, which an update redraws; an owner's own card is kept.
///
/// A file page ([fileId] and [file] set) has no snapshot: [file] is the
/// `file` block, which for a private file holds only what is already public
/// (its transactions and its data's cipher), never its name, size or type.
String buildPublicationJson({
  required String driveId,
  required String rootFolderId,
  String? folderId,
  String? fileId,
  Map<String, Object>? file,
  required String privacy,
  required String owner,
  String? ownerName,
  String? snapshotTxId,
  Map<String, String>? snapshotTags,
  required String title,
  required String description,
  int? fileCount,
  List<String> keywords = const [],
  Map<String, Object>? license,
  Map<String, String> images = const {},
  bool generatedCard = false,
  required String publishedAt,
  ({String release, String manifest})? viewer,
  List<String> names = const [],
}) {
  return _json({
    'version': fileId != null ? filePublicationVersion : publicationVersion,
    'driveId': driveId,
    'rootFolderId': rootFolderId,
    'scope': fileId != null
        ? {'type': 'file', 'fileId': fileId}
        : folderId != null
            ? {'type': 'folder', 'folderId': folderId}
            : {'type': 'drive'},
    'privacy': privacy,
    'owner': owner,
    if (ownerName != null && ownerName.isNotEmpty) 'ownerName': ownerName,
    if (fileId == null)
      'snapshot': {
        'path': 'snapshot',
        'txId': snapshotTxId,
        'tags': _sorted(snapshotTags ?? const {}),
      },
    if (file != null) 'file': _sorted(file),
    'title': title,
    'description': description,
    if (fileCount != null) 'fileCount': fileCount,
    if (keywords.isNotEmpty) 'keywords': keywords,
    if (license != null) 'license': license,
    if (images.isNotEmpty) 'images': images,
    if (generatedCard) 'generatedSocialCard': true,
    'publishedAt': publishedAt,
    // The names pointing at this version, as ArDrive set them: a hint,
    // checked against the gateway before a visitor sees one (docs/NAMES.md).
    if (names.isNotEmpty) 'names': names,
    if (viewer != null)
      'viewer': {'release': viewer.release, 'manifest': viewer.manifest},
  });
}

/// `publishedAt`'s form: ISO 8601 in UTC, to the second.
String publicationTimestamp(DateTime time) =>
    '${time.toUtc().toIso8601String().split('.').first}Z';

String escapePublicationHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

// What the page writes is left out of the release's head first, so a scraper
// never sees two titles or ArDrive's own card. One-line tags only, which is
// how web/index.html writes them; its comments mention tags but are not tags.
final _replaced = [
  RegExp(r'^[ \t]*<title>[^<]*<\/title>[ \t]*\r?\n', multiLine: true),
  RegExp(r'^[ \t]*<meta name="description"[^>]*>[ \t]*\r?\n', multiLine: true),
  RegExp(r'^[ \t]*<meta name="theme-color"[^>]*>[ \t]*\r?\n', multiLine: true),
  RegExp(r'^[ \t]*<meta property="og:[^>]*>[ \t]*\r?\n', multiLine: true),
  RegExp(r'^[ \t]*<meta name="twitter:[^>]*>[ \t]*\r?\n', multiLine: true),
  // The release's own stops a visitor zooming (`user-scalable=no`); a page
  // lets them.
  RegExp(r'^[ \t]*<meta [^>]*name="viewport"[^>]*>[ \t]*\r?\n',
      multiLine: true),
];
final _iconLinks = [
  RegExp(r'^[ \t]*<link rel="(?:shortcut )?icon"[^>]*>[ \t]*\r?\n',
      multiLine: true),
  RegExp(r'^[ \t]*<link rel="apple-touch-icon"[^>]*>[ \t]*\r?\n',
      multiLine: true),
];

/// The release's `index.html` with the page's head written in, right after
/// `<meta charset>`. [socialImageUrl] is the absolute URL of the social
/// image's own transaction. Without [icons] the release's own stay. With
/// [filesPageLabel], a crawler that runs no script finds `files.html` (and
/// the head names `sitemap.xml`).
String buildPublicationIndexHtml(
  String releaseIndexHtml, {
  required String title,
  required String description,
  ({String small, String touch})? icons,
  String? socialImageUrl,
  String? filesPageLabel,
}) {
  var html = releaseIndexHtml;
  for (final pattern in [..._replaced, if (icons != null) ..._iconLinks]) {
    html = html.replaceAll(pattern, '');
  }
  final charset = RegExp(r'<meta charset="[^"]*"\s*\/?>', caseSensitive: false)
      .firstMatch(html);
  if (charset == null) {
    throw const FormatException('release index.html has no <meta charset>');
  }

  const e = escapePublicationHtml;
  final head = [
    '<meta name="ardrive-publication" content="publication.json">',
    '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
    '<title>${e(title)}</title>',
    '<meta name="description" content="${e(description)}">',
    '<meta name="theme-color" content="#F7F7F7" media="(prefers-color-scheme: light)">',
    '<meta name="theme-color" content="#080808" media="(prefers-color-scheme: dark)">',
    if (icons != null) ...[
      '<link rel="icon" sizes="32x32" href="${e(icons.small)}">',
      '<link rel="apple-touch-icon" href="${e(icons.touch)}">',
    ],
    '<meta property="og:title" content="${e(title)}">',
    '<meta property="og:description" content="${e(description)}">',
    '<meta property="og:type" content="website">',
    if (socialImageUrl != null) ...[
      '<meta property="og:image" content="${e(socialImageUrl)}">',
      '<meta name="twitter:card" content="summary_large_image">',
    ],
    if (filesPageLabel != null)
      '<link rel="sitemap" type="application/xml" href="sitemap.xml">',
  ];
  final at = charset.end;
  html = '${html.substring(0, at)}\n'
      '${head.map((line) => '    $line').join('\n')}${html.substring(at)}';
  if (filesPageLabel != null) {
    final body = RegExp(r'<body[^>]*>', caseSensitive: false).firstMatch(html);
    if (body == null) {
      throw const FormatException('release index.html has no <body>');
    }
    html = '${html.substring(0, body.end)}'
        '\n    <noscript><a href="files.html">${e(filesPageLabel)}</a></noscript>'
        '${html.substring(body.end)}';
  }
  return html;
}

/// A file `files.html` and `sitemap.xml` list: its path below the page's top
/// folder (folders, then its name) and its data transaction.
typedef PublicationListedFile = ({List<String> path, String id});

class _Folder {
  _Folder(this.name);

  final String name;
  final folders = <String, _Folder>{};
  final files = <({String name, String id})>[];
}

/// `files.html`: every file of the page as a link to its data on [gateway],
/// folders nested, for search engines and anything else that runs no script.
/// Lists at most [publicationFilesPageCap] files, the first of [files].
/// [moreLabel] holds `{count}`.
String buildPublicationFilesHtml({
  required String title,
  required List<PublicationListedFile> files,
  required String gateway,
  required String openLabel,
  required String moreLabel,
}) {
  const e = escapePublicationHtml;
  final listed = files.take(publicationFilesPageCap);
  final root = _Folder('');
  for (final file in listed) {
    var folder = root;
    for (final name in file.path.sublist(0, file.path.length - 1)) {
      folder = folder.folders.putIfAbsent(name, () => _Folder(name));
    }
    folder.files.add((name: file.path.last, id: file.id));
  }
  final lines = <String>[];
  void list(_Folder folder, int depth) {
    final pad = '  ' * depth;
    lines.add('$pad<ul>');
    for (final child in folder.folders.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name))) {
      lines.add('$pad  <li>${e(child.name)}');
      list(child, depth + 2);
      lines.add('$pad  </li>');
    }
    for (final file in folder.files.toList()
      ..sort((a, b) => a.name.compareTo(b.name))) {
      lines.add('$pad  <li><a href="${e('$gateway/${file.id}')}">'
          '${e(file.name)}</a></li>');
    }
    lines.add('$pad</ul>');
  }

  list(root, 1);
  final more = files.length - listed.length;
  return [
    '<!DOCTYPE html>',
    '<html>',
    '<head>',
    '  <meta charset="UTF-8">',
    '  <meta name="viewport" content="width=device-width, initial-scale=1">',
    '  <title>${e(title)}</title>',
    '</head>',
    '<body>',
    '  <h1>${e(title)}</h1>',
    '  <p><a href="./">${e(openLabel)}</a></p>',
    ...lines,
    if (more > 0) '  <p>${e(moreLabel.replaceAll('{count}', '$more'))}</p>',
    '</body>',
    '</html>',
    '',
  ].join('\n');
}

/// `sitemap.xml`: the same files as `files.html`, as gateway data links.
String buildPublicationSitemap({
  required List<PublicationListedFile> files,
  required String gateway,
}) =>
    [
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
      for (final file in files.take(publicationFilesPageCap))
        '  <url><loc>${escapePublicationHtml('$gateway/${file.id}')}</loc></url>',
      '</urlset>',
      '',
    ].join('\n');

/// The page manifest: every path of the release, then the page's own paths
/// over them, sorted; `index.html` is the index and the fallback.
/// [releaseManifest] is the release manifest's JSON, decoded.
String buildPublicationManifest(
  Map<String, dynamic> releaseManifest,
  Map<String, String> pagePaths,
) {
  if (releaseManifest['manifest'] != 'arweave/paths') {
    throw const FormatException('the release is not an arweave/paths manifest');
  }
  final releasePaths =
      (releaseManifest['paths'] as Map? ?? const {}).cast<String, dynamic>();
  final paths = _sorted<dynamic>({
    ...releasePaths,
    for (final entry in pagePaths.entries) entry.key: {'id': entry.value},
  });
  final index = paths['index.html'];
  if (index == null) throw const FormatException('the page has no index.html');
  return _json({
    'manifest': 'arweave/paths',
    'version': '0.2.0',
    'index': {'path': 'index.html'},
    'fallback': {'id': index['id']},
    'paths': paths,
  });
}
