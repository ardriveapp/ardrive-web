import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';

import 'components.dart';

Future<void> showConfirmSeedphraseDialog({
  required BuildContext context,
}) {
  return showDialog(
    context: context,
    builder: (BuildContext context) => AppDialog(
      title: 'Download Wallet',
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          children: [],
        ),
      ),
    ),
  );
}
