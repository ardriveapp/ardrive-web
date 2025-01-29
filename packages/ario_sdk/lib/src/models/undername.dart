import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';

class ARNSUndername extends Equatable {
  final String name;
  final String domain;
  final ARNSRecord record;

  const ARNSUndername._({
    required this.name,
    required this.record,
    required this.domain,
  });

  @override
  List<Object?> get props => [name, record, domain];
}

/// Factory for creating ARNSUndername instances with consistent TTL handling
class ARNSUndernameFactory {
  /// Creates a new undername with the default TTL
  static ARNSUndername create({
    required String name,
    required String domain,
    required String transactionId,
  }) {
    return ARNSUndername._(
      name: name,
      domain: domain,
      record: ARNSRecord(
        transactionId: transactionId,
        ttlSeconds: ARNSRecord.defaultTtlSeconds,
      ),
    );
  }

  static ARNSUndername createDefaultUndername({
    required String domain,
    required String transactionId,
  }) {
    return create(
      name: '@',
      domain: domain,
      transactionId: transactionId,
    );
  }
}
