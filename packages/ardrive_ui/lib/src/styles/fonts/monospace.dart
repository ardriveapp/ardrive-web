import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Roboto Mono, the face for code, text-file previews, the note editor, and
/// IDs, addresses and keys, whole or shortened. Wavehaus stays the brand face
/// everywhere else.
///
/// It is loaded the first time something asks for it, not at startup: a font
/// listed in the pubspec's fonts block is in the font manifest, and Flutter
/// web downloads every font there before the first frame. Until it arrives,
/// text in it falls back to Wavehaus, and redraws in Roboto Mono once loaded.
///
/// Use it through [ArdriveTypographyNew.code], which starts the load.
abstract final class ArDriveMonospace {
  /// The family name the face is registered under.
  static const family = 'ArDriveRobotoMono';

  /// Drawn in while the face loads, and if it can't: the brand face.
  static const fallback = ['packages/ardrive_ui/Wavehaus'];

  static const _asset =
      'packages/ardrive_ui/assets/fonts/mono/RobotoMono-Regular.ttf';

  static Future<void>? _loading;

  /// Every Roboto Mono character is this many ems wide.
  static const advance = 0.6;

  /// How wide [text] is in Roboto Mono at [fontSize], with a pixel to spare.
  /// Give an ID or address that sits beside other things this width, with
  /// `softWrap: false`, so nothing moves when the face arrives and replaces
  /// the narrower fallback.
  ///
  /// Pass the reader's [textScaler] (`MediaQuery.textScalerOf(context)`):
  /// the text grows with their text size, and a box of the unscaled width
  /// cut off the end of the address.
  ///
  /// The spare pixel matters: the browser measures a line a fraction wider
  /// than its characters' advances, and a box of the exact width wrapped the
  /// last character out of sight.
  static double widthOf(
    String text,
    double fontSize, {
    TextScaler textScaler = TextScaler.noScaling,
  }) =>
      (text.characters.length * advance * textScaler.scale(fontSize))
          .ceilToDouble() +
      1;

  /// Reads the font file. Replaced in tests to count or fail loads.
  @visibleForTesting
  static Future<ByteData> Function() readFont = () => rootBundle.load(_asset);

  /// Loads the face, once. Later calls share the first load. A failed load is
  /// forgotten, so the next request tries again; the text stays in Wavehaus
  /// meanwhile.
  static Future<void> ensureLoaded() {
    return _loading ??= (FontLoader(family)..addFont(readFont()))
        .load()
        .catchError((Object _) => _loading = null);
  }

  @visibleForTesting
  static void resetForTesting() {
    _loading = null;
    readFont = () => rootBundle.load(_asset);
  }
}
