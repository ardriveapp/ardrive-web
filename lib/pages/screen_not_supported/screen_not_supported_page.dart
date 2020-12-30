import 'package:flutter/material.dart';

class ScreenNotSupportedPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Material(
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyText2,
          textAlign: TextAlign.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/brand/logo-vert-no-subtitle.png',
                  height: 126,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 32),
                Text('This screen size is too small.',
                    style: Theme.of(context).textTheme.headline6),
                const SizedBox(height: 16),
                Text('Please access ArDrive on a device with a larger screen.'),
              ],
            ),
          ),
        ),
      );
}
