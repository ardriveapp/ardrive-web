import 'dart:convert';
import 'dart:io';

import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_files.dart';
import 'package:flutter_test/flutter_test.dart';

/// The publisher's files against the golden files `tool/publication`
/// writes for the same inputs (`node tool/publication/golden.mjs`): the tool
/// is the reference, byte for byte.
void main() {
  const dir = 'test/publication/fixtures/golden';
  final input = json.decode(File('$dir/inputs.json').readAsStringSync())
      as Map<String, dynamic>;
  final publication = input['publication'] as Map<String, dynamic>;
  final labels = (input['labels'] as Map).cast<String, String>();
  final gateway = input['gateway'] as String;
  final files = [
    for (final file in input['files'] as List)
      (
        path: (file['path'] as List).cast<String>(),
        id: file['id'] as String,
      ),
  ];
  String golden(String name) => File('$dir/$name.golden').readAsStringSync();

  String publicationJson() {
    final viewer = publication['viewer'] as Map;
    return buildPublicationJson(
      driveId: publication['driveId'],
      rootFolderId: publication['rootFolderId'],
      folderId: publication['folderId'],
      privacy: publication['privacy'],
      owner: publication['owner'],
      ownerName: publication['ownerName'],
      snapshotTxId: publication['snapshotTxId'],
      snapshotTags: (publication['snapshotTags'] as Map).cast<String, String>(),
      title: publication['title'],
      description: publication['description'],
      fileCount: publication['fileCount'],
      keywords: (publication['keywords'] as List).cast<String>(),
      license: (publication['license'] as Map).cast<String, Object>(),
      images: (publication['images'] as Map).cast<String, String>(),
      generatedCard: publication['generatedCard'] as bool,
      publishedAt: publication['publishedAt'],
      viewer: (release: viewer['release'], manifest: viewer['manifest']),
    );
  }

  test('publication.json matches the tool', () {
    expect(publicationJson(), golden('publication.json'));
  });

  test('and the viewer reads it back', () {
    final config = PublicationConfig.parse(publicationJson());
    expect(config.title, publication['title']);
    expect(config.ownerName, publication['ownerName']);
    expect(config.license?.params, {
      'License-Fee': 'One-Time-0.1',
      'Commercial-Use': 'Allowed',
    });
  });

  test('names go into publication.json and are read back', () {
    final viewer = publication['viewer'] as Map;
    final text = buildPublicationJson(
      driveId: publication['driveId'],
      rootFolderId: publication['rootFolderId'],
      privacy: publication['privacy'],
      owner: publication['owner'],
      snapshotTxId: publication['snapshotTxId'],
      snapshotTags: (publication['snapshotTags'] as Map).cast<String, String>(),
      title: publication['title'],
      description: publication['description'],
      publishedAt: publication['publishedAt'],
      viewer: (release: viewer['release'], manifest: viewer['manifest']),
      names: ['docs_acme', 'acme'],
    );

    expect(json.decode(text)['names'], ['docs_acme', 'acme']);
    expect(PublicationConfig.parse(text).names, ['docs_acme', 'acme']);
    expect(PublicationConfig.parse(publicationJson()).names, isEmpty,
        reason: 'absent without names');
  });

  test('index.html matches the tool', () {
    expect(
      buildPublicationIndexHtml(
        input['releaseIndexHtml'],
        title: publication['title'],
        description: publication['description'],
        icons: (small: 'icon-32.png', touch: 'icon-180.png'),
        socialImageUrl: input['socialImageUrl'],
        filesPageLabel: labels['filesPage'],
      ),
      golden('index.html'),
    );
  });

  test('files.html and sitemap.xml match the tool', () {
    expect(
      buildPublicationFilesHtml(
        title: publication['title'],
        files: files,
        gateway: gateway,
        openLabel: labels['open']!,
        moreLabel: labels['more']!,
      ),
      golden('files.html'),
    );
    expect(
      buildPublicationSitemap(files: files, gateway: gateway),
      golden('sitemap.xml'),
    );
  });

  test('the ArFS tags match the tool', () {
    final publicationId = input['publicationId'] as String;
    List<Map<String, String>> asJson(List<PublicationTag> tags) => [
          for (final t in tags) {'name': t.name, 'value': t.value}
        ];
    expect(
      '${const JsonEncoder.withIndent('  ').convert({
            'entity': asJson(publicationEntityTags(
              driveId: publication['driveId'],
              publicationId: publicationId,
              folderId: publication['folderId'],
            )),
            'part': asJson(publicationPartTags(publicationId)),
          })}\n',
      golden('tags.json'),
    );
  });

  test('the manifest matches the tool', () {
    expect(
      buildPublicationManifest(
        input['releaseManifest'],
        (input['pagePaths'] as Map).cast<String, String>(),
      ),
      golden('manifest.json'),
    );
  });

  test('files.html and sitemap.xml stop at the cap and say how many more', () {
    final many = [
      for (var i = 0; i < publicationFilesPageCap + 3; i++)
        (path: ['f$i.txt'], id: 'id$i'),
    ];
    final html = buildPublicationFilesHtml(
      title: 't',
      files: many,
      gateway: gateway,
      openLabel: 'Open',
      moreLabel: 'And {count} more files.',
    );
    expect('<li><a '.allMatches(html), hasLength(publicationFilesPageCap));
    expect(html, contains('And 3 more files.'));
    expect(
      '<url>'
          .allMatches(buildPublicationSitemap(files: many, gateway: gateway)),
      hasLength(publicationFilesPageCap),
    );
  });

  test('publishedAt is UTC to the second', () {
    expect(
      publicationTimestamp(DateTime.utc(2026, 10, 23, 18, 2, 11, 456)),
      '2026-10-23T18:02:11Z',
    );
  });
}
