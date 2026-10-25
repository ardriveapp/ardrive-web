import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// One artifact of a share handover - a link or an access key - in a
/// [ArDriveCopyField], with the app's translations for its messages.
///
/// The link and the key are copied one at a time, on purpose: a private file
/// is handed over as two artifacts meant to travel through different channels.
/// Anything carrying key material - the key, or a link with the key in it - is
/// [isSecret], and starts masked until the sharer reveals it.
class CopyableShareArtifact extends StatelessWidget {
  const CopyableShareArtifact({
    super.key,
    required this.label,
    required this.text,
    required this.copyLabel,
    required this.revealLabel,
    this.isSecret = false,
    this.alignsWithSecret = false,
    this.isKey = false,
  });

  final String label;

  /// The value displayed, and the value Copy puts on the clipboard.
  final String text;

  final String copyLabel;

  /// The accessible name of the reveal control, which is icon-only.
  final String revealLabel;

  /// Whether this artifact carries key material.
  final bool isSecret;

  /// Whether a secret is shown with this artifact, so the two fields keep the
  /// same width.
  final bool alignsWithSecret;

  /// Whether this artifact is an access key on its own, which is drawn in
  /// monospace so every character can be told apart. A link stays in the
  /// body face, key in it or not: it reads as an address to open, not as
  /// characters to check one by one.
  final bool isKey;

  @override
  Widget build(BuildContext context) {
    final localizations = appLocalizationsOf(context);
    return ArDriveCopyField(
      label: label,
      text: text,
      copyLabel: copyLabel,
      copiedLabel: localizations.copied,
      copyFailedLabel: localizations.couldNotCopy,
      revealLabel: revealLabel,
      isSecret: isSecret,
      alignsWithSecret: alignsWithSecret,
      isMonospace: isKey,
    );
  }
}
