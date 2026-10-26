import 'package:equatable/equatable.dart';

enum ArNSNameType { lease, permabuy }

/// A name an ArNS wallet owns or controls, as the ArNS registry has it.
class ArNSNameData extends Equatable {
  const ArNSNameData({
    required this.name,
    required this.processId,
    required this.type,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.undernameLimit,
  });

  final String name;

  /// The ANT: the Solana asset that holds the name's records.
  final String processId;
  final ArNSNameType type;

  /// Milliseconds since the epoch.
  final int startTimestamp;

  /// When a lease ends, in milliseconds; null for a permanent name.
  final int? endTimestamp;
  final int undernameLimit;

  factory ArNSNameData.fromJson(Map<String, dynamic> json) => ArNSNameData(
        name: json['name'] as String,
        processId: json['processId'] as String,
        type: json['type'] == 'lease'
            ? ArNSNameType.lease
            : ArNSNameType.permabuy,
        startTimestamp: (json['startTimestamp'] as num).toInt(),
        endTimestamp: (json['endTimestamp'] as num?)?.toInt(),
        undernameLimit: (json['undernameLimit'] as num).toInt(),
      );

  @override
  List<Object?> get props =>
      [name, processId, type, startTimestamp, endTimestamp, undernameLimit];
}
