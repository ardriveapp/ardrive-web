import 'package:ardrive/theme/colors.dart';
import 'package:flutter/material.dart';

class ProfileAuthShell extends StatelessWidget {
  final Widget illustration;
  final Widget content;

  ProfileAuthShell({this.illustration, this.content});

  @override
  Widget build(BuildContext context) => Material(
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: kDarkColor,
                child: Center(
                  child: illustration,
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo-vert-no-subtitle.png',
                    height: 126,
                    fit: BoxFit.contain,
                  ),
                  Container(height: 16),
                  content,
                ],
              ),
            ),
          ],
        ),
      );
}
