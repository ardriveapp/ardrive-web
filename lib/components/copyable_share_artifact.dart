import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A read-only field holding one artifact of a share handover, with its own
/// copy affordance.
///
/// The link and the key are copied one at a time, on purpose - a private file
/// is handed over as two artifacts meant to travel through different channels.
///
/// ## Why [isSecret] masks by default
///
/// The recipient typing an access key gets an obscured field
/// (`shared_file_locked_view.dart`). The sharer handing that key out used to
/// get it rendered in full, which is backwards: **typing a key is a private
/// act, but handing one over is the moment a screen is most likely to be
/// shared, recorded or screenshotted.** Anything that carries key material -
/// the key itself, or a link with the key embedded - is masked here until the
/// sharer deliberately reveals it.
///
/// Masking never blocks the common path: [text] is copied from the value the
/// caller passed, not from what the field displays, so Copy works while masked.
class CopyableShareArtifact extends StatefulWidget {
  const CopyableShareArtifact({
    super.key,
    required this.label,
    required this.controller,
    required this.text,
    required this.copyLabel,
    required this.revealLabel,
    this.isSecret = false,
  });

  final String label;
  final TextEditingController controller;

  /// What the copy button puts on the clipboard. Taken from the caller rather
  /// than from [controller], which is only how the value is displayed - and
  /// which may be showing dots.
  final String text;

  final String copyLabel;

  /// The accessible name of the reveal control, which is icon-only.
  final String revealLabel;

  /// Whether this artifact carries key material, and so starts masked behind
  /// a reveal toggle.
  final bool isSecret;

  @override
  State<CopyableShareArtifact> createState() => _CopyableShareArtifactState();
}

class _CopyableShareArtifactState extends State<CopyableShareArtifact> {
  bool _isRevealed = false;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final isMasked = widget.isSecret && !_isRevealed;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: ArDriveTextFieldNew(
            // [ArDriveTextFieldNew] copies `obscureText` into its own state in
            // `initState` and never syncs it again, so toggling the property
            // on a mounted field does nothing. The key forces a fresh one -
            // the same trick, for the same reason, that the file share dialog
            // uses on its checkbox. Safe here because the field is read only
            // and its value lives on the controller, so a remount loses
            // nothing.
            key: ValueKey(isMasked),
            label: widget.label,
            controller: widget.controller,
            isEnabled: false,
            obscureText: isMasked,
            // Deliberately not the field's own `showObfuscationToggle`: it
            // renders inside the decoration of a disabled field, which
            // swallows the tap, so the mask could never be lifted. Asserted by
            // `test/components/copyable_share_artifact_test.dart`.
            showObfuscationToggle: false,
          ),
        ),
        if (widget.isSecret) ...[
          const SizedBox(width: 8),
          // Material's `IconButton` rather than the `GestureDetector` +
          // `ArDriveClickArea` pair used elsewhere: this control has no visible
          // label, so it needs the keyboard focus and the announced name that
          // a raw gesture detector does not provide.
          IconButton(
            icon: isMasked
                ? ArDriveIcons.eyeClosed(color: colorTokens.textMid)
                : ArDriveIcons.eyeOpen(color: colorTokens.textMid),
            onPressed: () => setState(() => _isRevealed = !_isRevealed),
            tooltip: widget.revealLabel,
            splashRadius: 20,
          ),
        ],
        const SizedBox(width: 16),
        CopyButton(
          positionX: 4,
          positionY: 40,
          copyMessageColor: colorTokens.containerRed,
          showCopyText: true,
          text: widget.text,
          child: Text(
            widget.copyLabel,
            style: typography
                .paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textMid,
                )
                .copyWith(
                  decoration: TextDecoration.underline,
                ),
          ),
        ),
      ],
    );
  }
}
