import 'package:ardrive/authentication/login/views/tiles/tiles_view.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';

/// What the sign-in page shows on its first paint and loads itself: the
/// panel's logo. The bento waits until the panel is usable (`_Bento` in
/// login_page.dart) and loads its own pictures then.
@visibleForTesting
List<String> firstLoginImages() => [Resources.images.brand.logo1];

/// Starts loading [firstLoginImages] before the app's first frame, and
/// returns at once: started from `main`, while the config loads, the logo is
/// decoded by the time the panel paints. Into the image cache, under the key
/// `Image.asset` makes (the asset has one resolution).
///
/// Nothing heavier: an SVG parsed here (flutter_svg parses on the main thread
/// on the web) held a throttled phone's start back by seconds, and pictures
/// fetched here competed with the database's own download.
void preCacheFirstLoginAssets() {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  final configuration = ImageConfiguration(
    bundle: rootBundle,
    devicePixelRatio: view?.devicePixelRatio ?? 1.0,
    platform: defaultTargetPlatform,
  );
  for (final path in firstLoginImages()) {
    final stream = AssetImage(path).resolve(configuration);
    late final ImageStreamListener listener;
    void done() => stream.removeListener(listener);
    listener = ImageStreamListener(
      (_, __) => done(),
      onError: (_, __) => done(),
    );
    stream.addListener(listener);
  }
}

/// The pictures the sign-in screen shows only after its first paint: the
/// bento's second group of people (10 s in) and the wallet-created step's two
/// pictures.
///
/// What the first paint shows is not here: those widgets load their own
/// pictures as they build, and loading them again here would only queue
/// behind them.
@visibleForTesting
List<String> laterLoginImages() => [
      Resources.images.login.bentoBox.profile4,
      Resources.images.login.bentoBox.profile5,
      Resources.images.login.bentoBox.profile6,
      Resources.images.login.whatIsAKeyfile,
      Resources.images.login.aboutSecurity,
    ];

/// The bento's feature slides after the first (5 s apart), for the theme in
/// view.
@visibleForTesting
List<String> laterLoginSvgs({required bool light}) =>
    bentoFeatureArt(light: light).skip(1).toList();

/// Loads [laterLoginImages] and [laterLoginSvgs] once the sign-in panel is
/// up, one picture a frame, so none of it competes with the first paint.
///
/// flutter_svg parses an SVG on the main thread on the web (its `compute`
/// runs inline there). This used to run on the app's first frame, before the
/// panel, and parsed seven SVGs, six of which no screen shows any more: the
/// page stalled for up to 1.6 s on a desktop and 9 s on a throttled phone,
/// and the database worker's replies waited behind it. Waits [delay] first,
/// and stops if [context] goes away.
Future<void> preCacheLaterLoginAssets(
  BuildContext context, {
  Duration delay = const Duration(seconds: 1),
}) async {
  await Future<void>.delayed(delay);
  if (!context.mounted) return;

  final light = ArDriveTheme.of(context).themeData.name == 'light';

  for (final path in laterLoginImages()) {
    if (!context.mounted) return;
    // Decoded by the browser; awaited only so the next one starts a frame
    // later.
    await precacheImage(AssetImage(path), context);
    await SchedulerBinding.instance.endOfFrame;
  }

  if (!kIsWeb) return;

  for (final path in laterLoginSvgs(light: light)) {
    if (!context.mounted) return;
    // Cached under the key `SvgPicture.asset` looks up.
    await SvgAssetLoader(path).loadBytes(null);
    await SchedulerBinding.instance.endOfFrame;
  }
}
