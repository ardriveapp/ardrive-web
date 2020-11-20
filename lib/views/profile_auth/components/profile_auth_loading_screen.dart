import 'package:ardrive/misc/misc.dart';
import 'package:flutter/material.dart';

import 'profile_auth_shell.dart';

class ProfileAuthLoadingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ProfileAuthShell(
        illustration: Image.asset(
          R.images.profile.profileUnlock,
          fit: BoxFit.contain,
        ),
        content: Center(child: CircularProgressIndicator()),
      );
}
