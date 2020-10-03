import 'package:flutter/material.dart';

Future<bool> showConfirmationDialog(BuildContext context,
        {String title, String content, String confirmingActionLabel}) =>
    showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: content != null ? Text(content) : null,
        actions: <Widget>[
          TextButton(
            child: Text('CANCEL'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: Text(confirmingActionLabel),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
