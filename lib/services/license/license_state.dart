import 'package:ardrive/services/license/licenses/licenses.dart';
import 'package:equatable/equatable.dart';

enum LicenseType {
  udl,
  ccBy,
  unknown,
}

class LicenseMeta extends Equatable {
  final LicenseType licenseType;
  final String licenseDefinitionTxId;
  final String name;
  final String shortName;
  final String version;
  final bool hasParams;

  const LicenseMeta({
    required this.licenseType,
    required this.licenseDefinitionTxId,
    required this.name,
    required this.shortName,
    required this.version,
    this.hasParams = false,
  });

  @override
  List<Object?> get props => [
        licenseType,
        licenseDefinitionTxId,
        name,
        shortName,
        version,
        hasParams,
      ];
}

abstract class LicenseParams extends Equatable {
  Map<String, String> toAdditionalTags() => {};

  @override
  List<Object?> get props => [toAdditionalTags()];
}

class EmptyParams extends LicenseParams {}

final licenseMetaMap = {
  LicenseType.udl: udlLicenseMeta,
  LicenseType.ccBy: ccByLicenseMeta,
};

class LicenseState extends Equatable {
  final LicenseMeta meta;
  final LicenseParams? params;

  const LicenseState({
    required this.meta,
    this.params,
  });

  @override
  List<Object?> get props => [meta, params];
}
