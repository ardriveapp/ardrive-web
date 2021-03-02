import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_parallax/flutter_parallax.dart';
import 'package:provider/provider.dart';
import 'package:responsive_builder/responsive_builder.dart';

class ProfileAuthOnboarding extends StatefulWidget {
  final Widget illustration;
  final PageController controller;

  final double contentWidthFactor;
  final Widget content;
  final Widget contentFooter;

  ProfileAuthOnboarding({
    this.illustration,
    this.contentWidthFactor,
    this.content,
    this.contentFooter,
    this.controller,
  });

  @override
  _ProfileAuthOnboardingState createState() => _ProfileAuthOnboardingState();
}

class _ProfileAuthOnboardingState extends State<ProfileAuthOnboarding> {
  int _onboardingStepIndex = 0;

  final controller = PageController();
  @override
  Widget build(BuildContext context) {
    Widget _buildOnboardingStepFooter() => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.chevron_left),
              label: Text('BACK'),
              onPressed: () {
                if (_onboardingStepIndex > 0) {
                  setState(() => _onboardingStepIndex--);
                } else {
                  context.read<ProfileAddCubit>().promptForWallet();
                }
              },
            ),
            TextButton(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('NEXT'),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onPressed: () {
                if (_onboardingStepIndex < 4) {
                  setState(() => _onboardingStepIndex++);
                } else {
                  context.read<ProfileAddCubit>().completeOnboarding();
                }
              },
            )
          ],
        );
    Widget _buildIllustrationSection(Widget illustration) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            illustration,
            const SizedBox(height: 48),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 256, minHeight: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var i = 0; i < 5; i++)
                    if (_onboardingStepIndex == i)
                      AnimatedContainer(
                        height: 16,
                        width: 16,
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                        ),
                      )
                    else
                      AnimatedContainer(
                        height: 8,
                        width: 8,
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: Colors.white70,
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                        ),
                      ),
                ],
              ),
            )
          ],
        );
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
                  PageView(
                    controller: controller,
                    children: [
                      DefaultTextStyle(
                        style: Theme.of(context).textTheme.headline6,
                        textAlign: TextAlign.center,
                        child: Builder(
                          builder: (context) => Column(
                            children: [
                              Text(
                                'WELCOME TO THE PERMAWEB',
                                style: Theme.of(context).textTheme.headline5,
                              ),
                              const SizedBox(height: 32),
                              Text(
                                  'ArDrive isn’t just another cloud sync app. It’s the beginning of a permanent hard drive.'),
                              const SizedBox(height: 16),
                              Text(
                                  'Any files you upload here will outlive you!'),
                              const SizedBox(height: 16),
                              Text(
                                  'That also means we do a few things differently.'),
                            ],
                          ),
                        ),
                      ),
                      DefaultTextStyle(
                        style: Theme.of(context).textTheme.headline6,
                        textAlign: TextAlign.center,
                        child: Builder(
                          builder: (context) => Column(
                            children: [
                              Text(
                                'PAY PER FILE',
                                style: Theme.of(context).textTheme.headline5,
                              ),
                              const SizedBox(height: 32),
                              Text('No subscriptions are needed!'),
                              const SizedBox(height: 16),
                              Text(
                                  'Instead of another monthly charge for empty space you don’t use, pay a few cents once and store your files forever on ArDrive.'),
                            ],
                          ),
                        ),
                      ),
                      DefaultTextStyle(
                        style: Theme.of(context).textTheme.headline6,
                        textAlign: TextAlign.center,
                        child: Builder(
                          builder: (context) => Column(
                            children: [
                              Text(
                                'SECONDS FROM FOREVER',
                                style: Theme.of(context).textTheme.headline5,
                              ),
                              const SizedBox(height: 32),
                              Text(
                                  'Decentralized, permanent data storage doesn’t happen in an instant.'),
                              const SizedBox(height: 16),
                              Text(
                                  'When the green checkmark appears next to your file, it has been uploaded to the PermaWeb.'),
                            ],
                          ),
                        ),
                      ),
                      DefaultTextStyle(
                        style: Theme.of(context).textTheme.headline6,
                        textAlign: TextAlign.center,
                        child: Builder(
                          builder: (context) => Column(
                            children: [
                              Text(
                                'TOTAL PRIVACY CONTROL',
                                style: Theme.of(context).textTheme.headline5,
                              ),
                              const SizedBox(height: 32),
                              Text(
                                  'Your choice: make files public or private using the best encryption.'),
                              const SizedBox(height: 16),
                              Text(
                                  'No one will see what you don’t want them to.'),
                            ],
                          ),
                        ),
                      ),
                      DefaultTextStyle(
                        style: Theme.of(context).textTheme.headline6,
                        textAlign: TextAlign.center,
                        child: Builder(
                          builder: (context) => Column(
                            children: [
                              Text(
                                'NEVER DELETED',
                                style: Theme.of(context).textTheme.headline5,
                              ),
                              const SizedBox(height: 32),
                              Text(
                                  'Remember: There is no delete button (for you or us)!'),
                              const SizedBox(height: 16),
                              Text(
                                  'Once uploaded, your data can’t be removed.'),
                              const SizedBox(height: 16),
                              Text(
                                  'Think twice before uploading all your teenage love poetry...'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
            _buildOnboardingStepFooter(),
          ],
        );
    Widget _buildIllustration() => Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: kDarkSurfaceColor,
            ),
            Parallax.outside(
              child: Image.asset(
                R.images.profile.permahillsBg,
                fit: BoxFit.contain,
              ),
              controller: controller,
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: PageView(
                  controller: controller,
                  children: [
                    _buildIllustrationSection(
                      Image.asset(
                        R.images.profile.newUserPermanent,
                        fit: BoxFit.contain,
                      ),
                    ),
                    _buildIllustrationSection(
                      Image.asset(
                        R.images.profile.newUserPayment,
                        fit: BoxFit.contain,
                      ),
                    ),
                    _buildIllustrationSection(
                      Image.asset(
                        R.images.profile.newUserUpload,
                        fit: BoxFit.contain,
                      ),
                    ),
                    _buildIllustrationSection(
                      Image.asset(
                        R.images.profile.newUserPrivate,
                        fit: BoxFit.contain,
                      ),
                    ),
                    _buildIllustrationSection(
                      Image.asset(
                        R.images.profile.newUserDelete,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
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
                widthFactor: widget.contentWidthFactor,
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
