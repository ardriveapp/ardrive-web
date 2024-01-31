import 'package:ardrive_ui/ardrive_ui.dart';

import '../license_state.dart';

const udlLicenseMeta = LicenseMeta(
  licenseType: LicenseType.udl,
  licenseDefinitionTxId: 'yRj4a5KMctX_uOmKWCFJIjmY8DeJcusVk6-HzLiM_t8',
  name: 'Universal Data License',
  shortName: 'UDL',
  version: '1.0',
  icon: ArDriveIcons.udl,
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
  static const String paymentAddress = 'Payment-Address';
}

enum UdlLicenseFeeType {
  oneTime,
}

Map<UdlLicenseFeeType, String> udlLicenseFeeTypeValues = {
  UdlLicenseFeeType.oneTime: 'One-Time',
};

String udlLicenseFeeOneTime(double amount) =>
    '${udlLicenseFeeTypeValues[UdlLicenseFeeType.oneTime]}-$amount';

class UdlLicenseParams extends LicenseParams {
  final double? licenseFeeAmount;
  final UdlCurrency licenseFeeCurrency;
  final UdlDerivation derivations;
  final UdlCommercialUse commercialUse;
  final String? paymentAddress;

  UdlLicenseParams({
    this.licenseFeeAmount,
    required this.licenseFeeCurrency,
    required this.derivations,
    required this.commercialUse,
    this.paymentAddress,
  });

  @override
  Map<String, String> toAdditionalTags() {
    // Null keys should be filtered
    final tags = <String, String>{};
    if (licenseFeeAmount != null) {
      tags[UdlTags.licenseFee] = udlLicenseFeeOneTime(licenseFeeAmount!);
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
    if (paymentAddress != null) {
      tags[UdlTags.paymentAddress] = paymentAddress!;
    }
    return tags;
  }

  static UdlLicenseParams fromAdditionalTags(
    Map<String, String> additionalTags,
  ) {
    final licenseFeeAmount = additionalTags.containsKey(UdlTags.licenseFee)
        ? double.tryParse(additionalTags[UdlTags.licenseFee]!
            .split('${udlLicenseFeeTypeValues[UdlLicenseFeeType.oneTime]}-')[1])
        : null;
    final licenseFeeCurrency = additionalTags.containsKey(UdlTags.currency)
        ? udlCurrencyValues.entries
            .firstWhere(
                (entry) => entry.value == additionalTags[UdlTags.currency])
            .key
        : UdlCurrency.u;
    final commercialUse = additionalTags.containsKey(UdlTags.commercialUse)
        ? udlCommercialUseValues.entries
            .firstWhere(
                (entry) => entry.value == additionalTags[UdlTags.commercialUse])
            .key
        : UdlCommercialUse.unspecified;
    final derivations = additionalTags.containsKey(UdlTags.derivations)
        ? udlDerivationValues.entries
            .firstWhere(
                (entry) => entry.value == additionalTags[UdlTags.derivations])
            .key
        : UdlDerivation.unspecified;
    final paymentAddress = additionalTags.containsKey(UdlTags.paymentAddress)
        ? additionalTags[UdlTags.paymentAddress]
        : null;

    return UdlLicenseParams(
      licenseFeeAmount: licenseFeeAmount,
      licenseFeeCurrency: licenseFeeCurrency,
      commercialUse: commercialUse,
      derivations: derivations,
      paymentAddress: paymentAddress,
    );
  }
}
