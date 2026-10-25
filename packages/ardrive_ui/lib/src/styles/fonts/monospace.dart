import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Roboto Mono, the face for code, text-file previews and the note editor.
/// Wavehaus stays the brand face everywhere else.
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
