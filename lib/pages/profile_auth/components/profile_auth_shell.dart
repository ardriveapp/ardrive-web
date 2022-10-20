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
  final bool resizeToAvoidBottomInset;

  const ProfileAuthShell({
    Key? key,
    required this.illustration,
    required this.content,
    this.contentWidthFactor,
    this.resizeToAvoidBottomInset = true,
    this.contentFooter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget _buildContent() => Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Container(
              constraints: BoxConstraints(
                minHeight: 512,
                maxHeight: MediaQuery.of(context).size.height - 64,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Image.asset(
                    Resources.images.brand.logoHorizontalNoSubtitleLight,
                    height: 126,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 32),
                  Flexible(child: content),
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
            SvgPicture.asset(
              Resources.images.profile.permahillsBg,
              fit: BoxFit.fitHeight,
            ),
            Container(
              decoration: BoxDecoration(
                  color: Colors.white,
                  gradient: LinearGradient(
                      begin: FractionalOffset.topCenter,
                      end: FractionalOffset.bottomCenter,
                      colors: [
                        Colors.grey.withOpacity(0.0),
                        Colors.black,
                      ],
                      stops: const [
                        0.0,
                        1.0
                      ])),
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
      mobile: Scaffold(
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        body: SingleChildScrollView(
          child: Padding(
              padding: const EdgeInsets.all(16.0), child: _buildContent()),
        ),
      ),
    );
  }
}
