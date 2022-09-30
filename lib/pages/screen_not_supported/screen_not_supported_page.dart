import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:flutter/material.dart';

class ScreenNotSupportedPage extends StatelessWidget {
  const ScreenNotSupportedPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Material(
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyText2!,
          textAlign: TextAlign.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  Resources.images.brand.logoHorizontalNoSubtitleLight,
                  height: 126,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 32),
                Text(appLocalizationsOf(context).weReSorryEmphasized,
                    style: Theme.of(context).textTheme.headline5),
                const SizedBox(height: 16),
                Text(appLocalizationsOf(context)
                    .ardriveIsOptimizedForLargeScreens),
                const SizedBox(height: 8),
                Text(appLocalizationsOf(context).tryOnAnotherDevice),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () =>
                      openUrl(url: 'https://ardrive.io/about/newsletter/'),
                  child: Text(appLocalizationsOf(context).subscribeEmphasized),
                ),
              ],
            ),
          ),
        ),
      );
}
