import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

import 'components.dart';

Future<void> showErrorDialog({
  required BuildContext context,
  Object? error,
  StackTrace? stackTrace,
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
            child: Text('CANCEL'),
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ],
      ),
    );
