/// Colours for the text inside Stripe's card field, which lives in an iframe
/// the app's theme can't reach. On the web they are pushed into the Stripe
/// element; elsewhere this does nothing.
library;

export 'stripe_card_colors_stub.dart'
    if (dart.library.html) 'stripe_card_colors_web.dart';
