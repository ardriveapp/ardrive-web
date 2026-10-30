import 'package:ardrive/locked_drives/domain/drive_fingerprint.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A drive's three-emoji fingerprint, the same three desktop shows.
///
/// It identifies the drive, not the password: a locked drive has no name to
/// show, and this is how the reader tells two of them apart, and checks the
/// one asking for a password is the one they meant. See [driveFingerprint].
///
/// Announced by name ("Drive emoji: milky way, shield, evergreen tree") rather
/// than as three pictures a screen reader may not name at all.
///
/// Drawn in [FingerprintEmojiFont], a colour font of just these 64 emoji.
class DriveFingerprint extends StatelessWidget {
  const DriveFingerprint({
    super.key,
    required this.driveId,
    this.size = 16,
  });

  final String driveId;

  /// The emoji's font size. 16 beside a name in a row; larger on its own.
  final double size;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    FingerprintEmojiFont.ensureLoaded();

    return ArDriveTooltip(
      message: strings.driveFingerprintTooltip,
      child: Semantics(
        label: strings
            .driveFingerprintLabel(driveFingerprintNames(driveId).join(', ')),
        excludeSemantics: true,
        child: Text(
          driveFingerprint(driveId),
          maxLines: 1,
          softWrap: false,
          // No colour is set, so none overrides the emoji's own.
          style: TextStyle(
            fontFamily: FingerprintEmojiFont.family,
            fontFamilyFallback: FingerprintEmojiFont.fallback,
            fontSize: size,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// The 64 fingerprint emoji from Noto Color Emoji (SIL Open Font License,
/// `assets/fonts/fingerprint-emoji/OFL.txt`), cut down to those code points
/// with Flutter's own `font-subset`: about 140 KB, colour bitmaps (CBDT).
///
/// Its own face rather than the engine's colour emoji fallback, which is a
/// 7.5 MB download and redraws every emoji anywhere in the app in colour.
/// Loaded the first time a fingerprint is drawn, never at startup: an asset,
/// not a pubspec font (see `ArDriveMonospace`).
abstract final class FingerprintEmojiFont {
  static const family = 'ArDriveFingerprintEmoji';

  static const asset = 'assets/fonts/fingerprint-emoji/FingerprintEmoji.ttf';

  static const licenseAsset = 'assets/fonts/fingerprint-emoji/OFL.txt';

  /// While the face loads, or where a browser can't draw its bitmaps, the
  /// platform's own colour emoji.
  static const fallback = [
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Noto Color Emoji',
  ];

  static Future<void>? _loading;

  /// Reads the font file. Replaced in tests.
  @visibleForTesting
  static Future<ByteData> Function() readFont = () => rootBundle.load(asset);

  /// Loads the face, once; a failed load is forgotten so the next fingerprint
  /// tries again.
  static Future<void> ensureLoaded() {
    return _loading ??= (FontLoader(family)..addFont(readFont()))
        .load()
        .catchError((Object _) => _loading = null);
  }

  /// Credits the font in the app's licences.
  static void registerLicense() {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        const ['Noto Color Emoji (drive fingerprints)'],
        await rootBundle.loadString(licenseAsset),
      );
    });
  }
}
