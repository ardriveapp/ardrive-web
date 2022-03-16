import 'package:ardrive/misc/misc.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ScreenNotSupportedPage extends StatelessWidget {
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
                  R.images.brand.logoHorizontalNoSubtitleLight,
                  height: 126,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 32),
                Text('WE\'RE SORRY!',
                    style: Theme.of(context).textTheme.headline5),
                const SizedBox(height: 16),
                Text('ArDrive is currently only optimized for larger screens.'),
                const SizedBox(height: 8),
                Text(
                    'Please try on another device or stay updated for our upcoming mobile app by subscribing to our newsletter below.'),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => launch(
                    'https://ardrive.io/about/newsletter/',
                  ),
                  child: Text('SUBSCRIBE'),
                ),
              ],
            ),
          ),
        ),
      );
}
