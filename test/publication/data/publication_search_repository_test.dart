import 'package:ardrive/publication/data/publication_search_repository.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/search/domain/search_coverage.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';
import '../publication_test_files.dart';

const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _root = '41520b33-28c1-4892-886b-b845a5709085';
const _a = 'aaaaaaaa-0000-4000-8000-000000000001';
const _b = 'bbbbbbbb-0000-4000-8000-000000000002';
const _hidden = '99999999-0000-4000-8000-000000000007';

PublicationConfig _config(PublicationScope scope) => PublicationConfig(
      version: 1,
      driveId: _drive,
      rootFolderId: _root,
      scope: scope,
      privacy: 'public',
      owner: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
      snapshot:
          const PublicationSnapshot(path: 'snapshot', txId: 't', tags: {}),
      title: 'Publication',
      description: '',
      images: const PublicationImages(),
      publishedAt: null,
      viewer: null,
    );

void main() {
  late Database db;

  Future<void> folder(String id, String name, String parent,
          {bool hidden = false}) =>
      db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
            id: id,
            driveId: _drive,
            name: name,
            parentFolderId: Value(parent),
            isHidden: Value(hidden),
            path: '',
          ));

  Future<void> file(
    String name,
    String parent, {
    bool hidden = false,
    String status = TransactionStatus.confirmed,
  }) =>
      insertPublicationFile(db,
          driveId: _drive,
          id: '$name-id',
          name: name,
          parentFolderId: parent,
          hidden: hidden,
          status: status);

  PublicationSearchRepository repository(PublicationConfig? config) =>
      PublicationSearchRepository(db.driveDao, config: () => config);

  Future<List<String>> names(PublicationConfig config, String query) async => [
        for (final result in await repository(config).search(query))
          switch (result.result) {
            FileEntry(:final name) => name,
            FolderEntry(:final name) => name,
            Drive(:final name) => 'drive:$name',
            _ => '?',
          },
      ];

  setUp(() async {
    db = getTestDb();
    // A drive named like what is searched for, so leaving it out shows.
    await db.driveDao.writePublicationDrive(
      driveId: _drive,
      rootFolderId: _root,
      ownerAddress: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
      privacy: 'public',
      name: 'report drive',
    );
    //   root: report-root.txt, report-hidden.txt (hidden)
    //   ├── a "report a": report-a.txt
    //   ├── b "report b": report-b.txt
    //   └── hidden "report hidden": report-in-hidden.txt
    await folder(_a, 'report a', _root);
    await folder(_b, 'report b', _root);
    await folder(_hidden, 'report hidden', _root, hidden: true);
    await file('report-root.txt', _root);
    await file('report-hidden.txt', _root, hidden: true);
    await file('report-a.txt', _a);
    await file('report-b.txt', _b);
    await file('report-in-hidden.txt', _hidden);
  });

  tearDown(() => db.close());

  test('a drive publication finds what it shows, and never the drive',
      () async {
    expect(
      await names(_config(const PublicationDriveScope()), 'report'),
      unorderedEquals([
        'report a',
        'report b',
        'report-root.txt',
        'report-a.txt',
        'report-b.txt',
      ]),
    );
  });

  test('places results in the publication, never naming what is above it',
      () async {
    final results = await repository(_config(const PublicationFolderScope(_a)))
        .search('report-a');
    expect(results.single.drive.name, 'Publication');
    expect(results.single.parentFolder, isNull);
  });

  test('never finds failed or pending uploads', () async {
    await file('report-failed.txt', _a, status: TransactionStatus.failed);
    await file('report-pending.txt', _a, status: TransactionStatus.pending);
    expect(
      await names(_config(const PublicationFolderScope(_a)), 'report'),
      ['report-a.txt'],
    );
  });

  test('a folder publication finds only inside its folder', () async {
    expect(
      await names(_config(const PublicationFolderScope(_a)), 'report'),
      ['report-a.txt'],
    );
  });

  test('a publication of a hidden folder finds inside it', () async {
    expect(
      await names(_config(const PublicationFolderScope(_hidden)), 'report'),
      ['report-in-hidden.txt'],
    );
  });

  test('matches outside a folder publication do not crowd out those inside',
      () async {
    for (var i = 0; i < 300; i++) {
      await file('report-b-$i.txt', _b);
    }
    expect(
      await names(_config(const PublicationFolderScope(_a)), 'report'),
      ['report-a.txt'],
    );
  });

  test('keeps as many of each kind as the app does', () async {
    for (var i = 0; i < 80; i++) {
      await file('report-$i.txt', _a);
    }
    final results = await repository(_config(const PublicationDriveScope()))
        .search('report');
    expect(
      results.whereType<dynamic>().where((r) => r.result is FileEntry).length,
      PublicationSearchRepository.resultsPerKind,
    );
  });

  test('finds nothing before the publication is open', () async {
    expect(await repository(null).search('report'), isEmpty);
    expect(
      await repository(null).coverage(includeHiddenDrives: false),
      SearchCoverage.unknown,
    );
  });

  test('covers the whole publication once it is open', () async {
    final coverage = await repository(_config(const PublicationDriveScope()))
        .coverage(includeHiddenDrives: false);
    expect(coverage.isComplete, isTrue);
  });
}
