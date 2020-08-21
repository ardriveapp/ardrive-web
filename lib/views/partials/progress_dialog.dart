import 'package:flutter/material.dart';

Future<bool> showProgressDialog(BuildContext context, String title) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: Text(title),
          content: Column(
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
