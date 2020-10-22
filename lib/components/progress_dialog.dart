import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';

import 'components.dart';

Future<bool> showProgressDialog(BuildContext context, String title) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AppDialog(
        dismissable: false,
        title: title,
        content: SizedBox(
          width: kSmallDialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: CircularProgressIndicator(),
              ),
            ],
          ),
        ),
      ),
    );
