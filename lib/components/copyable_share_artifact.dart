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
/// Masking never blocks the common path: Copy puts [text] on the clipboard, not
/// what the field displays, so it works while the field is showing dots.
///
/// ## Why the controller lives here
///
/// [text] is the whole input. An earlier version took a controller and left
/// each dialog to fill it from a bloc listener, which silently broke for any
/// cubit that reached its success state synchronously: a listener does not fire
/// for the state a bloc is already in, so the field rendered empty. Owning the
/// controller means the field always shows what it was given.
class CopyableShareArtifact extends StatefulWidget {
  const CopyableShareArtifact({
    super.key,
    required this.label,
    required this.text,
    required this.copyLabel,
    required this.revealLabel,
    this.isSecret = false,
  });

  final String label;

  /// The value displayed, and the value Copy puts on the clipboard.
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
  /// The reveal control's footprint, reserved on every row.
  ///
  /// Only a secret has something to reveal, but the slot is held open either
  /// way: without it, the field beside a reveal button is narrower than the one
  /// without, so a dialog showing a link above a key rendered two boxes of
  /// visibly different widths.
  static const _revealSlotWidth = 36.0;

  late final TextEditingController _controller =
      TextEditingController(text: widget.text);

  bool _isRevealed = false;

  @override
  void didUpdateWidget(covariant CopyableShareArtifact oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.text != widget.text) {
      _controller.text = widget.text;

      // A revealed secret stays revealed only for as long as it is the same
      // secret. Ticking "include the key in the link" swaps a keyless link for
      // one that carries the key, and that new value must not inherit the
      // previous one's revealed state.
      _isRevealed = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
            controller: _controller,
            isEnabled: false,
            obscureText: isMasked,
            // Deliberately not the field's own `showObfuscationToggle`: it
            // renders inside the decoration of a disabled field, which
            // swallows the tap, so the mask could never be lifted. Asserted by
            // `test/components/copyable_share_artifact_test.dart`.
            showObfuscationToggle: false,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: _revealSlotWidth,
          child: widget.isSecret
              // Material's `IconButton` rather than the `GestureDetector` +
              // `ArDriveClickArea` pair used elsewhere: this control has no
              // visible label, so it needs the keyboard focus and the announced
              // name that a raw gesture detector does not provide.
              ? IconButton(
                  icon: isMasked
                      ? ArDriveIcons.eyeClosed(color: colorTokens.textMid)
                      : ArDriveIcons.eyeOpen(color: colorTokens.textMid),
                  onPressed: () => setState(() => _isRevealed = !_isRevealed),
                  tooltip: widget.revealLabel,
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: _revealSlotWidth,
                    height: _revealSlotWidth,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
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
