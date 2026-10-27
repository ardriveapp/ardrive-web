import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';

/// One record of an ANT: an undername, or `@` for the name itself.
class ANTUndernameRecord extends Equatable {
  const ANTUndernameRecord({required this.undername, required this.record});

  final String undername;
  final ARNSRecord record;

  factory ANTUndernameRecord.fromJson(Map<String, dynamic> json) =>
      ANTUndernameRecord(
        undername: json['undername'] as String,
        record: ARNSRecord(
          transactionId: json['transactionId'] as String,
          ttlSeconds: (json['ttlSeconds'] as num).toInt(),
        ),
      );

  @override
  List<Object?> get props => [undername, record];
}

/// Who owns and controls an ANT, and where its name points.
class ANTSummary extends Equatable {
  const ANTSummary({
    required this.processId,
    required this.owner,
    required this.controllers,
    this.apexRecord,
  });

  final String processId;
  final String owner;
  final List<String> controllers;
  final ANTUndernameRecord? apexRecord;

  factory ANTSummary.fromJson(Map<String, dynamic> json) => ANTSummary(
        processId: json['processId'] as String,
        owner: json['owner'] as String,
        controllers: List<String>.from(json['controllers'] as List),
        apexRecord: json['apexRecord'] == null
            ? null
            : ANTUndernameRecord.fromJson(
                json['apexRecord'] as Map<String, dynamic>,
              ),
      );

  @override
  List<Object?> get props => [processId, owner, controllers, apexRecord];
}
