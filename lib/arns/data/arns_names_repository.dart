import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/domain/undername_validation.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';

/// Finds which records point at publications. A seam because publications
/// are found by GraphQL, not in the local database.
abstract class ArNSPublicationLookup {
  /// The publication version behind each of [txIds] that is one.
  Future<Map<String, ArNSPublicationItem>> publicationsFor(Set<String> txIds);
}

/// The signed-in owner's publications, through [PublicationRepository].
///
/// The owner's publications are read once and kept for [_cacheDuration]:
/// every names read asks, and a read is a GraphQL scan of the owner's
/// history. A version published since is told to the names repository with
/// [ArNSNamesRepository.rememberPublication].
class OwnerPublicationLookup implements ArNSPublicationLookup {
  OwnerPublicationLookup({
    required PublicationRepository repository,
    required String? Function() ownerAddress,
    DateTime Function()? clock,
  })  : _repository = repository,
        _ownerAddress = ownerAddress,
        _clock = clock ?? DateTime.now;

  final PublicationRepository _repository;
  final String? Function() _ownerAddress;
  final DateTime Function() _clock;

  static const _cacheDuration = Duration(minutes: 5);

  String? _cachedOwner;
  DateTime? _fetchedAt;
  Future<Map<String, List<Publication>>>? _cached;

  /// The owner's publications, read again once [_cacheDuration] has passed.
  /// Reads at the same time share one; a failed read is not kept.
  Future<Map<String, List<Publication>>> _publicationsOf(String owner) {
    final cached = _cached;
    final fetchedAt = _fetchedAt;
    if (cached != null &&
        _cachedOwner == owner &&
        (fetchedAt == null ||
            _clock().difference(fetchedAt) <= _cacheDuration)) {
      return cached;
    }
    late final Future<Map<String, List<Publication>>> read;
    read = _repository.publicationsOfOwner(owner).then((byDrive) {
      if (identical(_cached, read)) _fetchedAt = _clock();
      return byDrive;
    }, onError: (Object e, StackTrace st) {
      if (identical(_cached, read)) _cached = null;
      return Future<Map<String, List<Publication>>>.error(e, st);
    });
    _cachedOwner = owner;
    _fetchedAt = null;
    return _cached = read;
  }

  @override
  Future<Map<String, ArNSPublicationItem>> publicationsFor(
    Set<String> txIds,
  ) async {
    final owner = _ownerAddress();
    if (owner == null || txIds.isEmpty) return {};

    final found = <String, ArNSPublicationItem>{};
    final byDrive = await _publicationsOf(owner);
    for (final publications in byDrive.values) {
      for (final publication in publications) {
        for (final version in publication.versions) {
          if (!txIds.contains(version.txId)) continue;
          found[version.txId] = ArNSPublicationItem(
            publicationId: version.publicationId,
            driveId: version.driveId,
            scope: version.scope,
            isLatestVersion: version.txId == publication.latest.txId,
          );
        }
      }
    }
    return found;
  }
}

/// The names the linked ArNS wallet owns or manages, their records, and the
/// ArDrive items they point to (docs/NAMES.md). ArNS is the truth; the local
/// tables are a cache of it.
class ArNSNamesRepository {
  ArNSNamesRepository({
    required ArioSDK arioSDK,
    required ARNSDao dao,
    ArNSPublicationLookup? publications,
    DateTime Function()? clock,
  })  : _arioSDK = arioSDK,
        _dao = dao,
        _publications = publications,
        _clock = clock ?? DateTime.now;

  final ArioSDK _arioSDK;
  final ARNSDao _dao;
  final ArNSPublicationLookup? _publications;
  final DateTime Function() _clock;

  /// Every publication version a lookup has found this session, by
  /// transaction ID. A transaction never stops being the publication it was.
  final _knownPublications = <String, ArNSPublicationItem>{};

  /// Tells the lookup about a publication version just published, so a
  /// name pointing at it reads "Points to a publication" before GraphQL
  /// indexes it.
  void rememberPublication(String txId, ArNSPublicationItem publication) {
    _knownPublications[txId] = publication;
  }

  /// Record changes made this session, by ANT and undername, with when.
  /// Solana RPC nodes can answer a read with the state from before a write
  /// Turbo has already reported done, so every read applies them over what
  /// it got until [_madeLifetime] has passed.
  final _made = <(String, String), (ArNSRecordChange, DateTime)>{};

  static const _madeLifetime = Duration(minutes: 2);

  /// Tells every later read about a change just made, so a read that
  /// lags it doesn't show or cache the old record.
  void rememberChange(ArNSRecordChange change) {
    _made[(change.antId, change.undername)] = (change, _clock());
  }

  /// Forgets what this session learned: called when the ArNS wallet goes.
  void forgetSession() {
    _made.clear();
    _knownPublications.clear();
  }

  /// [read] with the changes made this session applied over its records.
  ArNSManagedName _withMade(ArNSManagedName read) {
    final now = _clock();
    _made.removeWhere((_, made) => now.difference(made.$2) > _madeLifetime);
    var records = read.records;
    for (final (change, _) in _made.values) {
      if (change.antId != read.processId) continue;
      records = [
        for (final r in records)
          if (r.undername != change.undername) r,
        if (change case ArNSSetRecord(:final transactionId, :final ttlSeconds))
          ArNSNameRecord(
            name: read.name,
            undername: change.undername,
            transactionId: transactionId,
            ttlSeconds: ttlSeconds,
          ),
      ];
    }
    return identical(records, read.records)
        ? read
        : read.withRecords(_sorted(records));
  }

  /// ANT record reads in flight at once: each is a program scan on the RPC.
  static const _recordReadConcurrency = 4;

  /// Reads [arnsAddress]'s names from ArNS, caches them, and returns them.
  ///
  /// The role comes from each ANT's owner, not from the access-control list,
  /// which lags a marketplace transfer. A name the address neither owns nor
  /// controls any more is left out: nothing it could change.
  Future<List<ArNSManagedName>> refresh(String arnsAddress) async {
    final listed = await _arioSDK.getArNSNamesForAddress(arnsAddress);
    final summaries = listed.isEmpty
        ? <String, ANTSummary>{}
        : await _arioSDK.getANTSummaries(
            listed.map((n) => n.processId).toSet().toList(),
          );

    final names = <ArNSManagedName>[];
    for (final name in listed) {
      final role = _roleOf(summaries[name.processId], arnsAddress);
      if (role == null) continue;
      names.add(ArNSManagedName(
        name: name.name,
        processId: name.processId,
        role: role,
        type: name.type,
        endTimestamp: name.endTimestamp == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(name.endTimestamp!),
        undernameLimit: name.undernameLimit,
        records: const [],
      ));
    }

    final withRecords = <ArNSManagedName>[];
    for (var i = 0; i < names.length; i += _recordReadConcurrency) {
      final chunk = names.skip(i).take(_recordReadConcurrency);
      withRecords.addAll(await Future.wait(chunk.map(_withRecords)));
    }
    withRecords.setAll(0, withRecords.map(_withMade).toList());

    await _dao.replaceNamesForAddress(
      arnsAddress: arnsAddress,
      names: [for (final n in withRecords) _toRow(n, arnsAddress)],
      records: [
        for (final n in withRecords)
          for (final r in n.records) _recordToRow(r),
      ],
    );

    return _mapTargets(withRecords);
  }

  /// What was last read for [arnsAddress], with no network but for
  /// publications.
  Future<List<ArNSManagedName>> cached(String arnsAddress) async {
    final rows =
        await _dao.getAntRecordsForAddress(arnsAddress: arnsAddress).get();
    if (rows.isEmpty) return [];

    final recordRows = await _dao
        .getARNSRecordsForDomains(domains: rows.map((r) => r.domain).toList())
        .get();
    final byDomain = <String, List<ArNSNameRecord>>{};
    for (final row in recordRows) {
      byDomain.putIfAbsent(row.domain, () => []).add(ArNSNameRecord(
            name: row.domain,
            undername: row.name,
            transactionId: row.transactionId,
            ttlSeconds: row.ttl,
          ));
    }

    return _mapTargets([
      for (final row in rows)
        ArNSManagedName(
          name: row.domain,
          processId: row.processId,
          role: row.role == ArNSRole.owner.name
              ? ArNSRole.owner
              : ArNSRole.controller,
          type: row.nameType == ArNSNameType.lease.name
              ? ArNSNameType.lease
              : ArNSNameType.permabuy,
          endTimestamp: row.endTimestamp == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(row.endTimestamp!),
          undernameLimit: row.undernameLimit,
          records: _sorted(byDomain[row.domain] ?? []),
        ),
    ]);
  }

  /// Re-reads one name's records after a change and caches them.
  ///
  /// [made] are the changes just made to it, remembered as with
  /// [rememberChange] and applied over what was read.
  Future<ArNSManagedName> refreshRecords(
    ArNSManagedName name, {
    List<ArNSRecordChange> made = const [],
  }) async {
    made.forEach(rememberChange);
    final updated = _withMade(await _withRecords(name));
    await _dao.replaceRecordsForDomain(
      name.name,
      [for (final r in updated.records) _recordToRow(r)],
    );
    return (await _mapTargets([updated])).single;
  }

  /// The ArDrive item behind each of [txIds] that is one: a file revision in
  /// the local database (deployments are files), else a publication.
  Future<Map<String, ArNSTarget>> resolveTargets(Set<String> txIds) async {
    if (txIds.isEmpty) return {};

    final targets = <String, ArNSTarget>{};
    final rows =
        await _dao.fileRevisionsForDataTxIds(txIds: txIds.toList()).get();
    for (final row in rows) {
      final item = ArNSFileItem(
        fileId: row.fileId,
        driveId: row.driveId,
        name: row.name,
        parentFolderId: row.parentFolderId,
        isManifest: row.dataContentType == ContentType.manifest,
        isHidden: row.isHidden,
        isLatestVersion: row.dataTxId == row.latestDataTxId,
      );
      final existing = targets[row.dataTxId];
      // The same data in two files: prefer the one where it is current.
      if (existing == null ||
          (!existing.isLatestVersion && item.isLatestVersion)) {
        targets[row.dataTxId] = item;
      }
    }

    final rest = txIds.difference(targets.keys.toSet());
    final publications = _publications;
    if (rest.isNotEmpty && publications != null) {
      var found = <String, ArNSPublicationItem>{};
      try {
        found = await publications.publicationsFor(rest);
        _knownPublications.addAll(found);
      } catch (e) {
        logger.w('Could not check names against publications: $e');
      }
      // A transaction that was a publication stays one: a failed or lagging
      // lookup must not turn it into "Points elsewhere" on one screen while
      // another, read earlier, still says publication.
      for (final txId in rest) {
        final publication = found[txId] ?? _knownPublications[txId];
        if (publication != null) targets[txId] = publication;
      }
    }
    return targets;
  }

  Future<ArNSManagedName> _withRecords(ArNSManagedName name) async {
    final records = await _arioSDK.getANTRecords(name.processId);
    return name.withRecords(_sorted([
      for (final r in records)
        ArNSNameRecord(
          name: name.name,
          undername: r.undername,
          transactionId: r.record.transactionId,
          ttlSeconds: r.record.ttlSeconds,
        ),
    ]));
  }

  Future<List<ArNSManagedName>> _mapTargets(List<ArNSManagedName> names) async {
    final targets = await resolveTargets({
      for (final n in names)
        for (final r in n.records) r.transactionId,
    });
    return [
      for (final n in names)
        n.withRecords([
          for (final r in n.records) r.withTarget(targets[r.transactionId]),
        ]),
    ];
  }

  static ArNSRole? _roleOf(ANTSummary? summary, String address) {
    if (summary == null) return null;
    if (summary.owner == address) return ArNSRole.owner;
    if (summary.controllers.contains(address)) return ArNSRole.controller;
    return null;
  }

  static List<ArNSNameRecord> _sorted(List<ArNSNameRecord> records) =>
      [...records]..sort((a, b) {
          if (a.isApex != b.isApex) return a.isApex ? -1 : 1;
          return a.undername.compareTo(b.undername);
        });

  static AntRecord _toRow(ArNSManagedName name, String arnsAddress) =>
      AntRecord(
        domain: name.name,
        processId: name.processId,
        arnsAddress: arnsAddress,
        role: name.role.name,
        nameType: name.type.name,
        endTimestamp: name.endTimestamp?.millisecondsSinceEpoch,
        undernameLimit: name.undernameLimit,
      );

  static ArnsRecord _recordToRow(ArNSNameRecord record) => ArnsRecord(
        id: literalArNSName(record.undername, record.name),
        domain: record.name,
        name: record.undername,
        transactionId: record.transactionId,
        ttl: record.ttlSeconds,
      );
}
