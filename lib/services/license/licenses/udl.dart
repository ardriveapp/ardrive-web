import 'package:collection/collection.dart';

import '../license_types.dart';

const udlLicenseMeta = LicenseMeta(
  licenseType: LicenseType.udl,
  licenseDefinitionTxId: 'yRj4a5KMctX_uOmKWCFJIjmY8DeJcusVk6-HzLiM_t8',
  name: 'Universal Data License',
  shortName: 'UDL',
  version: '1.0',
  hasParams: true,
);

enum UdlCurrency {
  u,
  ar,
}

Map<UdlCurrency, String> udlCurrencyValues = {
  UdlCurrency.u: 'U',
  UdlCurrency.ar: 'AR',
};

enum UdlCommercialUse {
  unspecified,
  allowed,
  allowedWithCredit,
}

Map<UdlCommercialUse, String> udlCommercialUseValues = {
  UdlCommercialUse.unspecified: '---',
  UdlCommercialUse.allowed: 'Allowed',
  UdlCommercialUse.allowedWithCredit: 'Allowed-With-Credit',
};

enum UdlDerivation {
  unspecified,
  allowedWithCredit,
  allowedWithIndication,
  allowedWithLicensePassthrough,
  // Allowed-With-RevenueShare,
}

Map<UdlDerivation, String> udlDerivationValues = {
  UdlDerivation.unspecified: '---',
  UdlDerivation.allowedWithCredit: 'Allowed-With-Credit',
  UdlDerivation.allowedWithIndication: 'Allowed-With-Indication',
  UdlDerivation.allowedWithLicensePassthrough:
      'Allowed-With-License-Passthrough',
};

class UdlTags {
  static const String licenseFee = 'License-Fee';
  static const String currency = 'Currency';
  static const String commercialUse = 'Commercial-Use';
  static const String derivations = 'Derivation';
}

class UdlLicenseParams extends LicenseParams {
  final double? licenseFeeAmount;
  final UdlCurrency licenseFeeCurrency;
  final UdlDerivation derivations;
  final UdlCommercialUse commercialUse;

  UdlLicenseParams({
    this.licenseFeeAmount,
    required this.licenseFeeCurrency,
    required this.derivations,
    required this.commercialUse,
  });

  @override
  Map<String, String> toAdditionalTags() {
    // Null keys should be filtered
    final tags = <String, String>{};
    if (licenseFeeAmount != null) {
      tags[UdlTags.derivations] = 'One-Time-${licenseFeeAmount.toString()}';
    }
    if (licenseFeeAmount != null && licenseFeeCurrency != UdlCurrency.u) {
      tags[UdlTags.currency] = udlCurrencyValues[licenseFeeCurrency]!;
    }
    if (commercialUse != UdlCommercialUse.unspecified) {
      tags[UdlTags.commercialUse] = udlCommercialUseValues[commercialUse]!;
    }
    if (derivations != UdlDerivation.unspecified) {
      tags[UdlTags.derivations] = udlDerivationValues[derivations]!;
    }
    return tags;
  }

  static UdlLicenseParams fromAdditionalTags(
    Map<String, String> additionalTags,
  ) {
    final licenseFeeAmountKey = additionalTags.keys
        .singleWhereOrNull((key) => key.startsWith('${UdlTags.licenseFee}-'));
    final licenseFeeAmount = licenseFeeAmountKey != null
        ? double.parse(additionalTags[licenseFeeAmountKey]!.split('-')[2])
        : null;
    final licenseFeeCurrency = additionalTags[UdlTags.currency] != null
        ? udlCurrencyValues.entries
            .firstWhere(
                (entry) => entry.value == additionalTags[UdlTags.currency])
            .key
        : UdlCurrency.u;
    final commercialUse = additionalTags[UdlTags.commercialUse] != null
        ? udlCommercialUseValues.entries
            .firstWhere(
                (entry) => entry.value == additionalTags[UdlTags.commercialUse])
            .key
        : UdlCommercialUse.unspecified;
    final derivations = additionalTags[UdlTags.derivations] != null
        ? udlDerivationValues.entries
            .firstWhere(
                (entry) => entry.value == additionalTags[UdlTags.derivations])
            .key
        : UdlDerivation.unspecified;

    return UdlLicenseParams(
      licenseFeeAmount: licenseFeeAmount,
      licenseFeeCurrency: licenseFeeCurrency,
      commercialUse: commercialUse,
      derivations: derivations,
    );
  }
}
