import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/license/license_types.dart';

extension LicenseAssertionsCompanionExtensions on LicenseAssertionsCompanion {
  LicenseType get licenseTypeEnum => LicenseType.values.firstWhere(
        (value) => value.name == licenseType.value,
      );
}
