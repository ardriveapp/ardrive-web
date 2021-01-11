import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';

class ProfileAuthShell extends StatelessWidget {
  final Widget illustration;

  final double contentWidthFactor;
  final Widget content;
  final Widget contentFooter;

  ProfileAuthShell(
      {this.illustration,
      this.contentWidthFactor,
      this.content,
      this.contentFooter});

  @override
  Widget build(BuildContext context) => Material(
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: kDarkSurfaceColor,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: illustration,
                  ),
                ),
              ),
            ),
            Expanded(
              child: FractionallySizedBox(
                widthFactor: contentWidthFactor,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Container(
                      constraints: const BoxConstraints(minHeight: 512),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            R.images.brand.logoVerticalNoSubtitle,
                            height: 126,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 32),
                          content,
                        ],
                      ),
                    ),
                    if (contentFooter != null) contentFooter,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
