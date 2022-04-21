import 'package:ardrive/misc/misc.dart';
import 'package:flutter/material.dart';

import '../../../utils/app_localizations_wrapper.dart';
import 'profile_auth_shell.dart';

class ProfileAuthLoadingScreen extends StatelessWidget {
  final bool isArConnect;

  const ProfileAuthLoadingScreen({Key? key, this.isArConnect = false})
      : super(key: key);
  @override
  Widget build(BuildContext context) => ProfileAuthShell(
        illustration: Image.asset(
          R.images.profile.profileUnlock,
          fit: BoxFit.contain,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isArConnect)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(appLocalizationsOf(context).pleaseRemainOnThisTab),
              ),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
}
