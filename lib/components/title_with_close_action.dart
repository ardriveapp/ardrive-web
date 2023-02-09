import 'dart:async';

import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';

const double dialogBorderRadius = 4.0;
const double actionButtonsPadding = 16.0;

class TitleWithCloseAction extends StatelessWidget {
  const TitleWithCloseAction({
    required this.title,
    this.onClose,
    Key? key,
  }) : super(key: key);

  final String title;
  final FutureOr<void> Function()? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: onClose != null ? 72 : 64,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(dialogBorderRadius),
          topRight: Radius.circular(dialogBorderRadius),
        ),
        color: kDarkSurfaceColor,
      ),
      child: Column(
        children: [
          if (onClose != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  color: kOnDarkSurfaceMediumEmphasis,
                  iconSize: 16,
                  visualDensity:
                      const VisualDensity(horizontal: -4, vertical: -4),
                ),
              ],
            )
          else
            const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(bottom: 12, right: 18, left: 18),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .headline6!
                        .copyWith(color: kOnDarkSurfaceHighEmphasis),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
