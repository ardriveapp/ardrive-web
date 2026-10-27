import 'package:ardrive/models/database/database.dart';
import 'package:drift/drift.dart';

part 'arns_dao.g.dart';

/// The local cache of the linked ArNS wallet's names and their records.
/// ArNS is the truth; this is for speed and search (docs/NAMES.md).
@DriftAccessor(include: {'./queries/arns_queries.drift'})
class ARNSDao extends DatabaseAccessor<Database> with _$ARNSDaoMixin {
  ARNSDao(super.attachedDatabase);

  /// Replaces everything cached for [arnsAddress] with [names] and
  /// [records], in one transaction.
  Future<void> replaceNamesForAddress({
    required String arnsAddress,
    required List<AntRecord> names,
    required List<ArnsRecord> records,
  }) async {
    await transaction(() async {
      final previous = await getAntRecordsForAddress(arnsAddress: arnsAddress)
          .map((r) => r.domain)
          .get();
      final domains = {...previous, ...names.map((n) => n.domain)}.toList();
      if (domains.isNotEmpty) {
        await deleteARNSRecordsForDomains(domains: domains);
      }
      await deleteAntRecordsForAddress(arnsAddress: arnsAddress);
      await batch((batch) {
        batch.insertAllOnConflictUpdate(antRecords, names);
        batch.insertAllOnConflictUpdate(arnsRecords, records);
      });
    });
  }

  /// Replaces the cached records of one name, after a change.
  Future<void> replaceRecordsForDomain(
    String domain,
    List<ArnsRecord> records,
  ) async {
    await transaction(() async {
      await deleteARNSRecordsForDomains(domains: [domain]);
      await batch((batch) {
        batch.insertAllOnConflictUpdate(arnsRecords, records);
      });
    });
  }
}
