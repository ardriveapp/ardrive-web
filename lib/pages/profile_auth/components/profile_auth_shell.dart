import 'package:ardrive/theme/theme.dart';
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
                color: kDarkSurfaceColor,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 512),
                      child: illustration,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/brand/logo-vert-no-subtitle.png',
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
