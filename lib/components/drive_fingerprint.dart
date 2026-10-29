import 'package:ardrive/locked_drives/domain/drive_fingerprint.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A drive's three-emoji fingerprint, the same three desktop shows.
///
/// It identifies the drive, not the password: a locked drive has no name to
/// show, and this is how the reader tells two of them apart, and checks the
/// one asking for a password is the one they meant. See [driveFingerprint].
///
/// Announced by name ("Drive emoji: milky way, shield, evergreen tree") rather
/// than as three pictures a screen reader may not name at all.
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
          // Emoji draw from the platform's colour emoji font; the brand face
          // has none. No colour is set, so none overrides theirs.
          style: TextStyle(fontSize: size, height: 1.2),
        ),
      ),
    );
  }
}
