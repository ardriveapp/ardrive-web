import 'package:ardrive/models/database/database.dart';
import 'package:drift/drift.dart';

part 'arns_dao.g.dart';

@DriftAccessor(include: {'./queries/arns_queries.drift'})
class ARNSDao extends DatabaseAccessor<Database> with _$ARNSDaoMixin {
  ARNSDao(super.attachedDatabase);

  Future<void> saveAntRecord({
    required String domain,
    required String transactionId,
    String? undername,
    required String recordId,
    required String processId,
  }) async {
    // Create a companion object with the values to insert
    final arnsRecord = ArnsRecordsCompanion(
      domain: Value(domain),
      transactionId: Value(transactionId),
      undername: Value(undername), // Nullable value
      recordId: Value(recordId), // Nullable value
      processId: Value(processId),
    );

    // Insert the new record into the table
    await into(arnsRecords).insert(arnsRecord);
  }
}
