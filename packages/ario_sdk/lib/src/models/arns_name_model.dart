import 'package:equatable/equatable.dart';

class ArNSNameModel extends Equatable {
  // TODO: maybe a list of records
  final String name;
  final String processId;
  final int records;
  final int undernameLimit;

  const ArNSNameModel({
    required this.name,
    required this.processId,
    required this.records,
    required this.undernameLimit,
  });

  @override
  List<Object?> get props => [name, processId, records, undernameLimit];

  @override
  String toString() {
    return 'ArNSNameModel(name: $name, processId: $processId, records: $records, undernameLimit: $undernameLimit)';
  }
}
