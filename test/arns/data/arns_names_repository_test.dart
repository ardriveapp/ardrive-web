import 'package:ardrive/arns/data/arns_names_repository.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockArioSDK extends Mock implements ArioSDK {}

class _FakePublications implements ArNSPublicationLookup {
  _FakePublications(this.found);

  final Map<String, ArNSPublicationItem> found;
  final asked = <Set<String>>[];

  @override
  Future<Map<String, ArNSPublicationItem>> publicationsFor(
    Set<String> txIds,
  ) async {
    asked.add(txIds);
    return {
      for (final e in found.entries)
        if (txIds.contains(e.key)) e.key: e.value,
    };
  }
}

const _wallet = 'arns-wallet';
const _antOwned = 'ant-owned';
const _antManaged = 'ant-managed';
const _antStale = 'ant-stale';

ANTUndernameRecord _record(String undername, String txId, [int ttl = 300]) =>
    ANTUndernameRecord(
      undername: undername,
      record: ARNSRecord(transactionId: txId, ttlSeconds: ttl),
    );

void main() {
  late Database db;
  late _MockArioSDK sdk;
  late _FakePublications publications;
  late ArNSNamesRepository repository;

  setUp(() async {
    db = getTestDb();
    sdk = _MockArioSDK();
    publications = _FakePublications({
      'pub-latest': const ArNSPublicationItem(
        publicationId: 'publication-1',
        driveId: 'drive-1',
        folderId: null,
        isLatestVersion: true,
      ),
    });
    repository = ArNSNamesRepository(
      arioSDK: sdk,
      dao: db.aRNSDao,
      publications: publications,
    );

    final date = DateTime(2026, 1, 1);
    await db.batch((batch) {
      batch.insertAll(db.fileEntries, [
        FileEntriesCompanion.insert(
          id: 'file-1',
          driveId: 'drive-1',
          parentFolderId: 'root',
          name: 'site',
          dataTxId: 'manifest-v2',
          size: 1,
          lastModifiedDate: date,
          dataContentType: const Value(ContentType.manifest),
          path: '',
        ),
      ]);
      batch.insertAll(db.fileRevisions, [
        for (final (tx, at) in [
          ('manifest-v1', date),
          ('manifest-v2', date.add(const Duration(days: 1))),
        ])
          FileRevisionsCompanion.insert(
            fileId: 'file-1',
            driveId: 'drive-1',
            name: 'site',
            parentFolderId: 'root',
            size: 1,
            lastModifiedDate: date,
            dataContentType: const Value(ContentType.manifest),
            metadataTxId: 'meta-$tx',
            dataTxId: tx,
            action: 'upload',
            dateCreated: Value(at),
          ),
      ]);
    });

    when(() => sdk.getArNSNamesForAddress(_wallet)).thenAnswer((_) async => [
          const ArNSNameData(
            name: 'acme',
            processId: _antOwned,
            type: ArNSNameType.lease,
            startTimestamp: 0,
            endTimestamp: 1800000000000,
            undernameLimit: 10,
          ),
          const ArNSNameData(
            name: 'friend',
            processId: _antManaged,
            type: ArNSNameType.permabuy,
            startTimestamp: 0,
            endTimestamp: null,
            undernameLimit: 10,
          ),
          const ArNSNameData(
            name: 'sold',
            processId: _antStale,
            type: ArNSNameType.permabuy,
            startTimestamp: 0,
            endTimestamp: null,
            undernameLimit: 10,
          ),
        ]);
    when(() => sdk.getANTSummaries(any())).thenAnswer((_) async => {
          _antOwned: const ANTSummary(
            processId: _antOwned,
            owner: _wallet,
            controllers: [],
          ),
          _antManaged: const ANTSummary(
            processId: _antManaged,
            owner: 'someone-else',
            controllers: [_wallet],
          ),
          // Still in the wallet's ACL after a transfer.
          _antStale: const ANTSummary(
            processId: _antStale,
            owner: 'buyer',
            controllers: [],
          ),
        });
    when(() => sdk.getANTRecords(_antOwned)).thenAnswer((_) async => [
          _record('blog', 'manifest-v1'),
          _record('@', 'manifest-v2', 3600),
          _record('news', 'pub-latest'),
          _record('old', 'somewhere-else'),
        ]);
    when(() => sdk.getANTRecords(_antManaged))
        .thenAnswer((_) async => [_record('@', 'somewhere-else')]);
  });

  tearDown(() => db.close());

  test('lists owned and managed names, leaving out stale ACL entries',
      () async {
    final names = await repository.refresh(_wallet);

    expect(names.map((n) => (n.name, n.role)), [
      ('acme', ArNSRole.owner),
      ('friend', ArNSRole.controller),
    ]);
    verifyNever(() => sdk.getANTRecords(_antStale));
  });

  test('reads lease end, undername limit and use', () async {
    final acme = (await repository.refresh(_wallet)).first;

    expect(acme.type, ArNSNameType.lease);
    expect(
        acme.endTimestamp, DateTime.fromMillisecondsSinceEpoch(1800000000000));
    expect(acme.undernameLimit, 10);
    expect(acme.undernamesUsed, 3);
    expect(acme.hasFreeUndername, isTrue);
    expect(acme.records.map((r) => r.undername), ['@', 'blog', 'news', 'old']);
    expect(acme.apex!.ttlSeconds, 3600);
  });

  test('maps records to files, older versions, publications or elsewhere',
      () async {
    final acme = (await repository.refresh(_wallet)).first;
    final byUndername = {for (final r in acme.records) r.undername: r};

    expect(
      byUndername['@']!.target,
      isA<ArNSFileItem>()
          .having((t) => t.fileId, 'fileId', 'file-1')
          .having((t) => t.isManifest, 'isManifest', isTrue)
          .having((t) => t.isLatestVersion, 'isLatestVersion', isTrue),
    );
    expect(
      byUndername['blog']!.target,
      isA<ArNSFileItem>()
          .having((t) => t.isLatestVersion, 'isLatestVersion', isFalse),
    );
    expect(
      byUndername['news']!.target,
      isA<ArNSPublicationItem>()
          .having((t) => t.publicationId, 'publicationId', 'publication-1'),
    );
    expect(byUndername['old']!.target, isNull);
    // Only what the database did not know is asked of publications.
    expect(publications.asked.single, {'pub-latest', 'somewhere-else'});
  });

  test('caches what it read, and the cache maps targets the same way',
      () async {
    final fresh = await repository.refresh(_wallet);

    final cached = await repository.cached(_wallet);

    expect(cached, fresh);
    expect(await repository.cached('another-wallet'), isEmpty);
  });

  test('a refresh replaces names the wallet no longer has', () async {
    await repository.refresh(_wallet);
    when(() => sdk.getArNSNamesForAddress(_wallet)).thenAnswer((_) async => []);

    expect(await repository.refresh(_wallet), isEmpty);
    expect(await repository.cached(_wallet), isEmpty);
    expect(await db.aRNSDao.select(db.arnsRecords).get(), isEmpty);
  });

  test('refreshRecords re-reads one name after a change', () async {
    final acme = (await repository.refresh(_wallet)).first;
    when(() => sdk.getANTRecords(_antOwned))
        .thenAnswer((_) async => [_record('@', 'manifest-v2')]);

    final updated = await repository.refreshRecords(acme);

    expect(updated.records.map((r) => r.undername), ['@']);
    final cached = await repository.cached(_wallet);
    expect(cached.first.records.map((r) => r.undername), ['@']);
  });

  group('refreshRecords after a change', () {
    // Turbo said the change was made, and the RPC node answered the re-read
    // with the records from before it: the Names page showed the old cache
    // time until it was opened again.
    test('keeps a record just set, whatever a lagging read says', () async {
      final acme = (await repository.refresh(_wallet)).first;
      final before = acme.records.firstWhere((r) => r.isApex);

      final updated = await repository.refreshRecords(acme, made: [
        ArNSSetRecord(
          antId: _antOwned,
          undername: '@',
          transactionId: before.transactionId,
          ttlSeconds: 3600,
        ),
        const ArNSSetRecord(
          antId: _antOwned,
          undername: 'docs',
          transactionId: 'docs-tx',
          ttlSeconds: 300,
        ),
      ]);

      expect(
        updated.records.map((r) => (r.undername, r.ttlSeconds)),
        containsAll([('@', 3600), ('docs', 300)]),
      );
      final cached = (await repository.cached(_wallet)).first;
      expect(cached.records.firstWhere((r) => r.isApex).ttlSeconds, 3600);
    });

    test('drops a record just removed', () async {
      when(() => sdk.getANTRecords(_antOwned)).thenAnswer(
          (_) async => [_record('@', 'manifest-v1'), _record('blog', 'b')]);
      final acme = (await repository.refresh(_wallet)).first;

      final updated = await repository.refreshRecords(acme, made: [
        const ArNSRemoveRecord(antId: _antOwned, undername: 'blog'),
      ]);

      expect(updated.records.map((r) => r.undername), ['@']);
    });

    test('ignores changes to another name', () async {
      final acme = (await repository.refresh(_wallet)).first;

      final updated = await repository.refreshRecords(acme, made: [
        const ArNSRemoveRecord(antId: 'another-ant', undername: '@'),
      ]);

      expect(updated.records, acme.records);
    });
  });

  group('a publication found once stays a publication', () {
    // The Names page said "Points to a publication" while the Add name
    // picker, read again moments later, said "Points elsewhere": the second
    // lookup failed or had not caught up.
    late _FlakyPublications flaky;

    setUp(() {
      flaky = _FlakyPublications({
        'pub-latest': const ArNSPublicationItem(
          publicationId: 'publication-1',
          driveId: 'drive-1',
          folderId: null,
          isLatestVersion: true,
        ),
      });
      repository = ArNSNamesRepository(
        arioSDK: sdk,
        dao: db.aRNSDao,
        publications: flaky,
      );
    });

    ArNSPointsToKind newsKind(List<ArNSManagedName> names) => arnsPointsToKind(
        names.first.records.firstWhere((r) => r.undername == 'news'));

    test('when a later lookup fails', () async {
      expect(newsKind(await repository.refresh(_wallet)),
          ArNSPointsToKind.publication);

      flaky.fails = true;

      expect(newsKind(await repository.refresh(_wallet)),
          ArNSPointsToKind.publication);
      expect(newsKind(await repository.cached(_wallet)),
          ArNSPointsToKind.publication);
    });

    test('when a later lookup misses it', () async {
      await repository.refresh(_wallet);

      flaky.found.clear();

      expect(newsKind(await repository.refresh(_wallet)),
          ArNSPointsToKind.publication);
      expect(
        arnsPointsToKind((await repository.refresh(_wallet))
            .first
            .records
            .firstWhere((r) => r.undername == 'old')),
        ArNSPointsToKind.elsewhere,
      );
    });
  });

  test('a publication lookup that fails leaves those records unmapped',
      () async {
    repository = ArNSNamesRepository(
      arioSDK: sdk,
      dao: db.aRNSDao,
      publications: _ThrowingPublications(),
    );

    final acme = (await repository.refresh(_wallet)).first;

    expect(
        acme.records.firstWhere((r) => r.undername == 'news').target, isNull);
    expect(acme.apex!.target, isNotNull);
  });

  group('lease state', () {
    final end = DateTime(2026, 6, 1);
    final name = ArNSManagedName(
      name: 'acme',
      processId: 'ant',
      role: ArNSRole.owner,
      type: ArNSNameType.lease,
      endTimestamp: end,
      undernameLimit: 10,
      records: const [],
    );

    test('blocked in the 14 days after the lease ends', () {
      expect(
          name.isInGracePeriod(end.subtract(const Duration(days: 1))), isFalse);
      expect(name.isInGracePeriod(end), isTrue);
      expect(name.isInGracePeriod(end.add(const Duration(days: 13))), isTrue);
      expect(name.isExpired(end.add(const Duration(days: 14))), isTrue);
    });
  });
}

class _FlakyPublications implements ArNSPublicationLookup {
  _FlakyPublications(this.found);

  final Map<String, ArNSPublicationItem> found;
  bool fails = false;

  @override
  Future<Map<String, ArNSPublicationItem>> publicationsFor(
    Set<String> txIds,
  ) async {
    if (fails) throw Exception('GraphQL failed');
    return {
      for (final e in found.entries)
        if (txIds.contains(e.key)) e.key: e.value,
    };
  }
}

class _ThrowingPublications implements ArNSPublicationLookup {
  @override
  Future<Map<String, ArNSPublicationItem>> publicationsFor(
    Set<String> txIds,
  ) async =>
      throw Exception('GraphQL failed');
}
