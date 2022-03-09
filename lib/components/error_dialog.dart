import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'components.dart';

Future<void> showErrorDialog({
  required BuildContext context,
  required Object error,
  required StackTrace stackTrace,
}) =>
    showDialog(
      context: context,
      builder: (BuildContext context) => AppDialog(
        title: AppLocalizations.of(context)!.errorLog,
        content: Column(
          children: [Text(stackTrace.toString())],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child:
                Text(AppLocalizations.of(context)!.cancelErrorDialogEmphasized),
          ),
        ],
      ),
    );
