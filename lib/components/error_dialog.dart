import 'package:flutter/material.dart';

import 'components.dart';

Future<void> showErrorDialog({
  required BuildContext context,
  required Object error,
  required StackTrace stackTrace,
}) =>
    showDialog(
      context: context,
      builder: (BuildContext context) => AppDialog(
        title: 'Error Log',
        content: Column(
          children: [Text(stackTrace.toString())],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text('CANCEL'),
          ),
        ],
      ),
    );
