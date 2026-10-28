import 'dart:async';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js_util' as js_util;

import 'package:ardrive/utils/logger.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_stripe_web/flutter_stripe_web.dart' show WebStripe;

Timer? _pending;

/// Styles the text inside Stripe's card element.
///
/// flutter_stripe_web passes only the text colour, as an Appearance variable,
/// which Stripe's classic card element ignores; its text stayed Stripe's dark
/// default, unreadable on a dark field. The element's own `style` option is
/// what reaches inside its iframe, so it is set here once the element exists:
/// the card field creates it a couple of frames after it is built.
void applyStripeCardColors({
  required Color text,
  required Color placeholder,
  required Color icon,
  required Color error,
  double fontSize = 14,
}) {
  _pending?.cancel();
  var attempts = 0;

  void tryApply(Timer? timer) {
    final element = WebStripe.element;
    if (element == null) {
      if (++attempts > 50) timer?.cancel();
      return;
    }
    timer?.cancel();
    try {
      js_util.callMethod<void>(element, 'update', [
        js_util.jsify({
          'style': {
            'base': {
              'color': _css(text),
              'iconColor': _css(icon),
              'fontSize': '${fontSize}px',
              '::placeholder': {'color': _css(placeholder)},
            },
            'invalid': {
              'color': _css(error),
              'iconColor': _css(error),
            },
          },
        }),
      ]);
    } catch (e) {
      logger.d('Could not style the Stripe card field: $e');
    }
  }

  _pending = Timer.periodic(const Duration(milliseconds: 100), tryApply);
}

String _css(Color color) =>
    'rgba(${color.red}, ${color.green}, ${color.blue}, ${(color.opacity).toStringAsFixed(3)})';
