import 'dart:ui';

/// How strongly a secret on screen (a recovery phrase) is blurred until the
/// user asks to see it. Strong enough that no word can be made out, even
/// from a screenshot or a camera.
const double secretBlurSigma = 10;

/// The same blur for text drawn only as its shadow: [Shadow.blurRadius]
/// is converted to a sigma as `radius * 0.57735 + 0.5`.
const double secretBlurShadowRadius = (secretBlurSigma - 0.5) / 0.57735;

/// [secretBlurSigma] as an image filter.
final ImageFilter secretBlurFilter =
    ImageFilter.blur(sigmaX: secretBlurSigma, sigmaY: secretBlurSigma);
