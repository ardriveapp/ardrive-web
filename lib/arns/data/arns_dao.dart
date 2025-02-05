import 'package:ardrive/models/database/database.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:ario_sdk/ario_sdk.dart';

part 'arns_dao.g.dart';

@DriftAccessor(include: {'./queries/arns_queries.drift'})
class ARNSDao extends DatabaseAccessor<Database> with _$ARNSDaoMixin {
  ARNSDao(super.attachedDatabase);

  Future<void> saveARNSRecord({
    required String domain,
    required String transactionId,
    String? undername,
    bool isActive = true,
    int ttl = ARNSRecord.defaultTtlSeconds,
    required String fileId,
  }) async {
    // Create a companion object with the values to insert
    final arnsRecord = ArnsRecordsCompanion(
      domain: Value(domain),
      transactionId: Value(transactionId),
      name: Value(undername ?? '@'), // Nullable value
      isActive: Value(isActive),
      ttl: Value(ttl),
      id: Value(const Uuid().v4()),
      fileId: Value(fileId),
    );

    // Insert the new record into the table
    await into(arnsRecords).insertOnConflictUpdate(arnsRecord);
  }

  Future<void> saveAntRecords(List<AntRecord> records) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(antRecords, records);
    });
  }

  Future<void> saveARNSRecords(List<ArnsRecord> records) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(arnsRecords, records);
    });
  }

  Future<void> updateARNSRecordActiveStatus({
    required String id,
    required bool isActive,
  }) async {
    final record = await getARNSRecordById(id: id).getSingle();

    await into(arnsRecords)
        .insertOnConflictUpdate(record.copyWith(isActive: Value(isActive)));
  }
}
