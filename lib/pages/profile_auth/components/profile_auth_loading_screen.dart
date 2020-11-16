import 'package:flutter/material.dart';

import 'profile_auth_shell.dart';

class ProfileAuthLoadingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ProfileAuthShell(
        illustration: Image.asset(
          'assets/images/illustrations/illus_profile_unlock.png',
          fit: BoxFit.scaleDown,
        ),
        content: Center(child: CircularProgressIndicator()),
      );
}
