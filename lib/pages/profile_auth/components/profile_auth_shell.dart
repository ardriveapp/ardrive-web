import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';

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
  Widget build(BuildContext context) {
    Widget _buildContent() => Column(
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
        );
    Widget _buildIllustration() => Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: kDarkSurfaceColor,
            ),
            FittedBox(
              fit: BoxFit.fitWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(R.images.profile.permahillsBg),
                  SizedBox(height: 128),
                ],
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: illustration,
              ),
            ),
          ],
        );
    return ScreenTypeLayout(
      desktop: Material(
        child: Row(
          children: [
            Expanded(
              child: _buildIllustration(),
            ),
            Expanded(
              child: FractionallySizedBox(
                widthFactor: contentWidthFactor,
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
      mobile: Material(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _buildContent(),
        ),
      ),
    );
  }
}
