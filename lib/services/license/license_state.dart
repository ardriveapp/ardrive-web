import 'package:ardrive/services/license/license.dart';
import 'package:equatable/equatable.dart';

/// Updating a license type version will require to update the corresponding [licenseMetaMap].
/// The [licenseMetaMap] is used to map the license type to the corresponding [LicenseMeta].
///
/// Please ensure to update the [licenseMetaMap] when adding a new license type.
enum LicenseType {
  udl,
  udlV2,
  ccBy,
  ccByV2,
  ccByNC,
  ccByNCND,
  ccByNCSA,
  ccByND,
  ccBySA,
  unknown,
}

enum LicenseCategory {
  cc,
  udl,
}

final licenseMetaMap = {
  LicenseType.udl: udlLicenseMeta,
  LicenseType.udlV2: udlLicenseMetaV2,
  LicenseType.ccBy: ccByLicenseMeta,
  LicenseType.ccByV2: ccByLicenseMetaV2,
  LicenseType.ccByNC: ccByNCLicenseMeta,
  LicenseType.ccByNCND: ccByNCNDLicenseMeta,
  LicenseType.ccByNCSA: ccByNCSAMeta,
  LicenseType.ccByND: ccByNDLicenseMeta,
  LicenseType.ccBySA: ccBySAMeta,
};

class LicenseMeta extends Equatable {
  final LicenseType licenseType;
  final String licenseDefinitionTxId;
  final String name;
  final String shortName;
  final bool hasParams;

  const LicenseMeta({
    required this.licenseType,
    required this.licenseDefinitionTxId,
    required this.name,
    required this.shortName,
    this.hasParams = false,
  });

  @override
  List<Object?> get props => [
        licenseType,
        licenseDefinitionTxId,
        name,
        shortName,
        hasParams,
      ];
}

abstract class LicenseParams extends Equatable {
  Map<String, String> toAdditionalTags() => {};

  @override
  List<Object?> get props => [toAdditionalTags()];
}

class EmptyParams extends LicenseParams {}

final licenseCategoryNames = {
  LicenseCategory.udl: 'Universal Data License - UDL',
  LicenseCategory.cc: 'Creative Commons - CC',
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
