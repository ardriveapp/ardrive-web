import 'package:ardrive/misc/resources.dart';
import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

/// The one thing every sync surface shows to say it is working.
///
/// There were three before this, and they did not agree: the drives list drew
/// a linear bar in `buttonPrimaryDefault`, the explorer's panel drew one in
/// `textHigh`, and the top bar turned a ring - so the same wait read as a red
/// bar on one screen and a white one on the next.
///
/// The plate stack is the loader this app already uses while it sets up an
/// account and while an upload is being prepared, so it is the mark a user has
/// been taught means "ArDrive is working". Sync had simply never used it.
///
/// It says nothing about *how far*: a measured bar still sits underneath it
/// where there is a real figure to show, and this stands alone where there is
/// not. That division is the point - motion means working, the bar means
/// progress, and neither pretends to be the other.
class SyncLoadingIndicator extends StatelessWidget {
  const SyncLoadingIndicator({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: LottieBuilder.asset(
        Resources.images.login.ardriveLoader,
        filterQuality: FilterQuality.high,
        frameRate: FrameRate.max,
        addRepaintBoundary: true,
        height: size,
        width: size,
      ),
    );
  }
}
