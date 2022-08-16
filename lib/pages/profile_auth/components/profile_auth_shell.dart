import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:responsive_builder/responsive_builder.dart';

class ProfileAuthShell extends StatelessWidget {
  final Widget illustration;

  final Widget content;
  final double? contentWidthFactor;
  final Widget? contentFooter;

  const ProfileAuthShell({
    Key? key,
    required this.illustration,
    required this.content,
    this.contentWidthFactor,
    this.contentFooter,
  }) : super(key: key);

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
                    Resources.images.brand.logoHorizontalNoSubtitleLight,
                    height: 126,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 32),
                  content,
                ],
              ),
            ),
            if (contentFooter != null) contentFooter!,
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
                  SvgPicture.asset(Resources.images.profile.permahillsBg),
                  const SizedBox(height: 128),
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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }
}
