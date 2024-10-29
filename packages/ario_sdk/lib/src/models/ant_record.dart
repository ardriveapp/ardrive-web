import 'package:equatable/equatable.dart';

class ANTRecord extends Equatable {
  final String domain;
  final String processId;

  const ANTRecord({
    required this.domain,
    required this.processId,
  });

  @override
  List<Object?> get props => [domain, processId];
}
