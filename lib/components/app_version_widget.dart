import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionWidget extends StatelessWidget {
  /// The text colour; the theme's low-emphasis text when not given.
  final Color? color;

  const AppVersionWidget({
    super.key,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: PackageInfo.fromPlatform(),
      builder: (BuildContext context, AsyncSnapshot<PackageInfo> snapshot) {
        final info = snapshot.data;
        if (info == null) {
          return const SizedBox(
            height: 32,
            width: 32,
          );
        }
        return Text(
          appLocalizationsOf(context).appVersion(appVersionText(info)),
          style: ArDriveTypographyNew.of(context).paragraphNormal(
            color:
                color ?? ArDriveTheme.of(context).themeData.colorTokens.textLow,
          ),
          textAlign: TextAlign.center,
        );
      },
    );
  }
}

/// The version as the app shows it: the release on the web, the release and
/// build elsewhere.
String appVersionText(PackageInfo info) =>
    kIsWeb ? info.version : '${info.version}+${info.buildNumber}';

/// Where What's new goes: the release page for [version] in a production
/// build, which is the one that is tagged, and the list of releases in a
/// staging or development build, which are not.
String whatsNewUrl(String version, Flavor flavor) => flavor == Flavor.production
    ? 'https://github.com/ardriveapp/ardrive-web/releases/tag/v$version'
    : 'https://github.com/ardriveapp/ardrive-web/releases';

/// The build's flavor, from the app's [ConfigService]; development where
/// none is provided (a widget test of part of the app).
Flavor appFlavorOf(BuildContext context) {
  try {
    return context.read<ConfigService>().flavor;
  } on ProviderNotFoundException {
    return Flavor.development;
  } on Exception {
    // Not loaded yet: the app loads it before it draws anything.
    return Flavor.development;
  }
}

/// Help's line about the app: "Version 2.90.0 · What's new".
///
/// The one place the version is shown in the signed-in app and on sign in:
/// it is what a reader asking for support is asked for, and Help is where
/// they are then.
class AppVersionHelpLine extends StatelessWidget {
  const AppVersionHelpLine({
    super.key,
    this.flavor,
    this.packageInfo,
  });

  /// Which release page What's new opens; the app's own when not given.
  final Flavor? flavor;

  /// For a test; read from the platform otherwise.
  final Future<PackageInfo>? packageInfo;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);

    return FutureBuilder<PackageInfo>(
      future: packageInfo ?? PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox.shrink();
        final style = typography.paragraphNormal(color: colorTokens.textMid);
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(strings.appVersion(appVersionText(info)), style: style),
            Text(' \u00b7 ', style: style),
            ArDriveLink(
              text: strings.whatsNew,
              external: true,
              onTap: () => openUrl(
                url: whatsNewUrl(info.version, flavor ?? appFlavorOf(context)),
              ),
            ),
          ],
        );
      },
    );
  }
}
