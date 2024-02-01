import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionWidget extends StatelessWidget {
  final Color color;

  const AppVersionWidget({
    Key? key,
    this.color = Colors.grey,
  }) : super(key: key);

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
        final literalVersion =
            kIsWeb ? info.version : '${info.version}+${info.buildNumber}';
        return Text(
          appLocalizationsOf(context).appVersion(literalVersion),
          style: ArDriveTypography.body.buttonNormalRegular(
            color: color,
          ),
          textAlign: TextAlign.center,
        );
      },
    );
  }
}
