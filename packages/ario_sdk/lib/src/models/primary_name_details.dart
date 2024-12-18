import 'package:equatable/equatable.dart';

class PrimaryNameDetails extends Equatable {
  final String primaryName;
  final String? logo;
  final String? recordId;

  const PrimaryNameDetails({
    required this.primaryName,
    this.logo,
    this.recordId,
  });

  @override
  List<Object?> get props => [primaryName, logo, recordId];

  PrimaryNameDetails copyWith({
    String? primaryName,
    String? logo,
    String? recordId,
  }) {
    return PrimaryNameDetails(
      primaryName: primaryName ?? this.primaryName,
      logo: logo ?? this.logo,
      recordId: recordId ?? this.recordId,
    );
  }
}
