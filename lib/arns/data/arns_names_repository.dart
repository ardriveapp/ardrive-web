import 'package:ardrive/arns/data/arns_dao.dart';
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
class OwnerPublicationLookup implements ArNSPublicationLookup {
  OwnerPublicationLookup({
    required PublicationRepository repository,
    required String? Function() ownerAddress,
  })  : _repository = repository,
        _ownerAddress = ownerAddress;

  final PublicationRepository _repository;
  final String? Function() _ownerAddress;

  @override
  Future<Map<String, ArNSPublicationItem>> publicationsFor(
    Set<String> txIds,
  ) async {
    final owner = _ownerAddress();
    if (owner == null || txIds.isEmpty) return {};

    final found = <String, ArNSPublicationItem>{};
    final byDrive = await _repository.publicationsOfOwner(owner);
    for (final publications in byDrive.values) {
      for (final publication in publications) {
        for (final version in publication.versions) {
          if (!txIds.contains(version.txId)) continue;
          found[version.txId] = ArNSPublicationItem(
            publicationId: version.publicationId,
            driveId: version.driveId,
            folderId: version.folderId,
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
  })  : _arioSDK = arioSDK,
        _dao = dao,
        _publications = publications;

  final ArioSDK _arioSDK;
  final ARNSDao _dao;
  final ArNSPublicationLookup? _publications;

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
  Future<ArNSManagedName> refreshRecords(ArNSManagedName name) async {
    final updated = await _withRecords(name);
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
      try {
        targets.addAll(await publications.publicationsFor(rest));
      } catch (e) {
        logger.w('Could not check names against publications: $e');
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
