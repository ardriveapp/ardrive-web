import 'package:ardrive/services/license/license_types.dart';
import 'package:ardrive/services/license/licenses/udl.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class LicenseSummary extends StatelessWidget {
  final LicenseState licenseState;
  late final Map<String, String> summaryItems;

  LicenseSummary({
    super.key,
    required this.licenseState,
  }) {
    summaryItems = licenseState.params is UdlLicenseParams
        ? udlLicenseSummary(licenseState.params as UdlLicenseParams)
        : {};
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // TODO: Localize
          'License',
          style: ArDriveTypography.body.smallRegular(
            color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
          ),
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    '${licenseState.meta.name} (${licenseState.meta.shortName})',
                style: ArDriveTypography.body.buttonLargeBold(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                ),
              ),
              const TextSpan(text: '   '),
              TextSpan(
                text: 'View',
                style: ArDriveTypography.body
                    .buttonLargeRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgSubtle,
                    )
                    .copyWith(
                      decoration: TextDecoration.underline,
                    ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () async {
                    final url =
                        'https://viewblock.io/arweave/tx/${licenseState.meta.licenseDefinitionTxId}';
                    await openUrl(url: url);
                  },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ...summaryItems.entries.expand(
          (entry) => [
            Text(
              entry.key,
              style: ArDriveTypography.body.smallRegular(
                color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
              ),
            ),
            Text(
              entry.value,
              style: ArDriveTypography.body.buttonLargeBold(
                color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              ),
            ),
            const SizedBox(height: 24),
          ],
        )
      ],
    );
  }

  Map<String, String> udlLicenseSummary(UdlLicenseParams udlLicenseParams) {
    final summary = <String, String>{};

    if (udlLicenseParams.licenseFeeAmount != null) {
      summary['License Fee'] = '${udlLicenseParams.licenseFeeAmount}';
      summary['License Currency'] =
          udlCurrencyValues[udlLicenseParams.licenseFeeCurrency]!;
    }
    if (udlLicenseParams.commercialUse != UdlCommercialUse.unspecified) {
      summary['Commercial Use'] =
          udlCommercialUseValues[udlLicenseParams.commercialUse]!;
    }
    if (udlLicenseParams.derivations != UdlDerivation.unspecified) {
      summary['Derivations'] =
          udlDerivationValues[udlLicenseParams.derivations]!;
    }

    return summary;
  }
}
