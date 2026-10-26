import 'package:equatable/equatable.dart';

/// A Solana wallet installed in this browser that can approve name changes.
class SolanaWalletInfo extends Equatable {
  const SolanaWalletInfo({required this.name, required this.icon});

  final String name;

  /// A data URI.
  final String icon;

  factory SolanaWalletInfo.fromJson(Map<String, dynamic> json) =>
      SolanaWalletInfo(
        name: json['name'] as String,
        icon: json['icon'] as String? ?? '',
      );

  @override
  List<Object?> get props => [name, icon];
}

/// A record write a controller signs and pays for itself.
enum ControllerWrite {
  /// A new record: rent for its account plus fees.
  createRecord('set-record'),

  /// An existing record: fees only.
  editRecord('edit-record'),

  /// Its rent comes back.
  removeRecord('remove-record');

  const ControllerWrite(this.workflow);

  final String workflow;
}

/// What a controller's write costs on Solana, in lamports.
class ControllerFeeEstimate extends Equatable {
  const ControllerFeeEstimate({
    required this.totalLamports,
    required this.feeLamports,
    required this.rentLamports,
    required this.rentReclaimedLamports,
  });

  /// What the wallet must hold up front.
  final int totalLamports;
  final int feeLamports;
  final int rentLamports;
  final int rentReclaimedLamports;

  factory ControllerFeeEstimate.fromJson(Map<String, dynamic> json) =>
      ControllerFeeEstimate(
        totalLamports: (json['totalLamports'] as num).toInt(),
        feeLamports: (json['feeLamports'] as num).toInt(),
        rentLamports: (json['rentLamports'] as num).toInt(),
        rentReclaimedLamports:
            (json['rentReclaimedLamports'] as num? ?? 0).toInt(),
      );

  @override
  List<Object?> get props =>
      [totalLamports, feeLamports, rentLamports, rentReclaimedLamports];
}

class ArioProgramIds extends Equatable {
  const ArioProgramIds({
    required this.core,
    required this.gar,
    required this.arns,
    required this.ant,
  });

  final String core;
  final String gar;
  final String arns;
  final String ant;

  factory ArioProgramIds.fromJson(Map<String, dynamic> json) => ArioProgramIds(
        core: json['core'] as String,
        gar: json['gar'] as String,
        arns: json['arns'] as String,
        ant: json['ant'] as String,
      );

  @override
  List<Object?> get props => [core, gar, arns, ant];
}

/// The clusters the bridge knows, from the SDK.
class ArioNetworkConfig extends Equatable {
  const ArioNetworkConfig({
    required this.mainnetRpcUrl,
    required this.devnetRpcUrl,
    required this.mainnetProgramIds,
    required this.devnetProgramIds,
    required this.isDevnet,
  });

  final String mainnetRpcUrl;
  final String devnetRpcUrl;
  final ArioProgramIds mainnetProgramIds;
  final ArioProgramIds devnetProgramIds;
  final bool isDevnet;

  factory ArioNetworkConfig.fromJson(Map<String, dynamic> json) =>
      ArioNetworkConfig(
        mainnetRpcUrl: json['mainnetRpcUrl'] as String,
        devnetRpcUrl: json['devnetRpcUrl'] as String,
        mainnetProgramIds: ArioProgramIds.fromJson(
          json['mainnetProgramIds'] as Map<String, dynamic>,
        ),
        devnetProgramIds: ArioProgramIds.fromJson(
          json['devnetProgramIds'] as Map<String, dynamic>,
        ),
        isDevnet: json['isDevnet'] == true,
      );

  @override
  List<Object?> get props =>
      [mainnetRpcUrl, devnetRpcUrl, mainnetProgramIds, devnetProgramIds, isDevnet];
}
