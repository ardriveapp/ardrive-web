import 'package:json_annotation/json_annotation.dart';

part 'gateway.g.dart';

@JsonSerializable(explicitToJson: true)
class Gateway {
  final int operatorStake;
  final String gatewayAddress;
  final String observerAddress;
  final Settings settings;
  final int startTimestamp;
  final int? endTimestamp;
  final int totalDelegatedStake;
  final Stats stats;
  final String status;

  Gateway({
    required this.operatorStake,
    required this.gatewayAddress,
    required this.observerAddress,
    required this.settings,
    required this.startTimestamp,
    this.endTimestamp,
    required this.totalDelegatedStake,
    required this.stats,
    required this.status,
  });

  factory Gateway.fromJson(Map<String, dynamic> json) =>
      _$GatewayFromJson(json);
  Map<String, dynamic> toJson() => _$GatewayToJson(this);
}

@JsonSerializable()
class Vault {
  final int balance;
  final int startTimestamp;
  final int endTimestamp;

  Vault({
    required this.balance,
    required this.startTimestamp,
    required this.endTimestamp,
  });

  factory Vault.fromJson(Map<String, dynamic> json) => _$VaultFromJson(json);
  Map<String, dynamic> toJson() => _$VaultToJson(this);
}

@JsonSerializable()
class Settings {
  final int port;
  final String protocol;
  final bool allowDelegatedStaking;
  final String fqdn;
  final int delegateRewardShareRatio;
  final String properties;
  final String note;
  final int minDelegatedStake;
  final String label;
  final bool autoStake;

  Settings({
    required this.port,
    required this.protocol,
    required this.allowDelegatedStaking,
    required this.fqdn,
    required this.delegateRewardShareRatio,
    required this.properties,
    required this.note,
    required this.minDelegatedStake,
    required this.label,
    required this.autoStake,
  });

  factory Settings.fromJson(Map<String, dynamic> json) =>
      _$SettingsFromJson(json);
  Map<String, dynamic> toJson() => _$SettingsToJson(this);
}

@JsonSerializable()
class Stats {
  final int failedConsecutiveEpochs;
  final int observedEpochCount;
  final int passedConsecutiveEpochs;
  final int totalEpochCount;
  final int prescribedEpochCount;
  final int passedEpochCount;
  final int failedEpochCount;

  Stats({
    required this.failedConsecutiveEpochs,
    required this.observedEpochCount,
    required this.passedConsecutiveEpochs,
    required this.totalEpochCount,
    required this.prescribedEpochCount,
    required this.passedEpochCount,
    required this.failedEpochCount,
  });

  factory Stats.fromJson(Map<String, dynamic> json) => _$StatsFromJson(json);
  Map<String, dynamic> toJson() => _$StatsToJson(this);
}

@JsonSerializable(explicitToJson: true)
class Delegate {
  final List<Vault> vaults;
  final int delegatedStake;
  final int startTimestamp;

  Delegate({
    required this.vaults,
    required this.delegatedStake,
    required this.startTimestamp,
  });

  factory Delegate.fromJson(Map<String, dynamic> json) =>
      _$DelegateFromJson(json);
  Map<String, dynamic> toJson() => _$DelegateToJson(this);
}
