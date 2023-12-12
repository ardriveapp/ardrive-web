import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/license/license_types.dart';

extension LicenseAssertionsCompanionExtensions on LicenseAssertionsCompanion {
  LicenseType get licenseTypeEnum => LicenseType.values.firstWhere(
        (value) => value.name == licenseType.value,
      );

  /// Returns a list of [NetworkTransactionsCompanion] representing the metadata and data transactions
  /// of this entity.
  List<NetworkTransactionsCompanion> getTransactionCompanions() => [
        NetworkTransactionsCompanion.insert(
            id: metadataTxId.value, dateCreated: dateCreated),
        NetworkTransactionsCompanion.insert(
            id: dataTxId.value, dateCreated: dateCreated),
      ];
}
