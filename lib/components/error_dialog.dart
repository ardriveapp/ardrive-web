import 'package:flutter/material.dart';

import '../../../utils/app_localizations_wrapper.dart';
import 'components.dart';

Future<void> showErrorDialog({
  required BuildContext context,
  required Object error,
  required StackTrace stackTrace,
}) =>
    showDialog(
      context: context,
      builder: (BuildContext context) => AppDialog(
        title: appLocalizationsOf(context).errorLog,
        content: Column(
          children: [Text(stackTrace.toString())],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(appLocalizationsOf(context).cancelEmphasized),
          ),
        ],
      ),
    );
