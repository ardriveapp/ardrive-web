import 'package:ardrive/components/license/view_license_definition.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive/services/license/licenses/udl.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';

class LicenseSummary extends StatelessWidget {
  final LicenseState licenseState;

  final bool showLicenseName;

  late final Map<String, String> paramsSummaryItems;

  LicenseSummary({
    super.key,
    this.showLicenseName = true,
    required this.licenseState,
  }) {
    if (licenseState.params is UdlLicenseParams) {
      paramsSummaryItems =
          udlLicenseSummary(licenseState.params as UdlLicenseParams);
    } else {
      paramsSummaryItems = licenseState.params?.toAdditionalTags() ?? {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLicenseName) ...[
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
                  text: licenseState.meta.nameWithShortName,
                  style: ArDriveTypography.body.buttonLargeBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  ),
                ),
                if (licenseState.meta.licenseType != LicenseType.unknown) ...[
                  const WidgetSpan(
                    child: SizedBox(width: 16),
                  ),
                  viewLicenseDefinitionTextSpan(
                    context,
                    licenseState.meta.licenseDefinitionTxId,
                  ),
                ]
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        ...paramsSummaryItems.entries.expand(
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
