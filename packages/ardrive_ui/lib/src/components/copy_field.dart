import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A read-only field holding a value to hand over, such as a link or a key,
/// with a Copy link beside it.
///
/// A secret ([isSecret]) starts masked behind a reveal toggle: handing a key
/// over is the moment a screen is most likely to be shared or recorded. Copy
/// takes [text], not what the field shows, so it works while masked.
///
/// The widget owns its controller, so the field always shows [text]. An
/// earlier version took a controller filled from a bloc listener, which never
/// fired for a state the bloc was already in, and the field rendered empty.
///
/// Every string is passed in: this package has no translations.
class ArDriveCopyField extends StatefulWidget {
  const ArDriveCopyField({
    super.key,
    required this.label,
    required this.text,
    required this.copyLabel,
    required this.copiedLabel,
    required this.copyFailedLabel,
    this.revealLabel,
    this.isSecret = false,
    this.alignsWithSecret = false,
    this.isMonospace = false,
  }) : assert(!isSecret || revealLabel != null,
            'A secret needs a label for its reveal control');

  final String label;

  /// The value displayed, and the value Copy puts on the clipboard.
  final String text;

  /// The Copy link's text, such as "Copy link".
  final String copyLabel;

  /// Shown for a moment after a copy that worked, and one that the browser
  /// refused. A phone's browser refuses when it doesn't count the tap as the
  /// reader's own.
  final String copiedLabel;
  final String copyFailedLabel;

  /// The accessible name of the reveal control, which is icon-only.
  final String? revealLabel;

  /// Whether the value is key material, and so starts masked.
  final bool isSecret;

  /// Whether a secret is shown with this field, such as a link above its
  /// key. The reveal control's space is then kept here too, so the two fields
  /// are the same width. Kept everywhere, it left a gap before Copy on every
  /// link with no key.
  final bool alignsWithSecret;

  /// Whether the value is an ID or a key, drawn in monospace so every
  /// character can be told apart. A link stays in the body face.
  final bool isMonospace;

  @override
  State<ArDriveCopyField> createState() => _ArDriveCopyFieldState();
}

class _ArDriveCopyFieldState extends State<ArDriveCopyField> {
  static const _revealSlotWidth = 36.0;

  late final TextEditingController _controller =
      TextEditingController(text: widget.text);
  final _copyKey = GlobalKey();

  bool _isRevealed = false;

  /// Whether the last copy worked, while its message shows.
  bool? _copied;
  OverlayEntry? _message;

  @override
  void didUpdateWidget(covariant ArDriveCopyField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.text != widget.text) {
      _controller.text = widget.text;

      // A revealed secret stays revealed only while it is the same secret:
      // swapping a keyless link for one that carries the key must not inherit
      // the old one's revealed state.
      _isRevealed = false;
    }
  }

  @override
  void dispose() {
    _removeMessage();
    _controller.dispose();
    super.dispose();
  }

  void _removeMessage() {
    if (_message?.mounted ?? false) _message!.remove();
    _message = null;
  }

  void _toggleReveal() => setState(() => _isRevealed = !_isRevealed);

  Future<void> _copy() async {
    // Asked for at once, inside the tap: a browser refuses a write that comes
    // later. Then waited on, because it can refuse this one too.
    final write = Clipboard.setData(ClipboardData(text: widget.text));

    bool copied;
    try {
      await write;
      copied = true;
    } catch (_) {
      copied = false;
    }
    if (!mounted) return;

    // Tapped again while the last answer still shows: a retry after a refusal
    // that worked says so.
    if (_message != null) {
      if (copied != _copied) {
        _copied = copied;
        _message!.markNeedsBuild();
      }
      return;
    }

    _copied = copied;
    _message = _buildMessage();
    Overlay.of(context).insert(_message!);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _removeMessage();
    });
  }

  OverlayEntry _buildMessage() {
    final box = _copyKey.currentContext!.findRenderObject() as RenderBox;
    final position = box.localToGlobal(Offset.zero);
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return OverlayEntry(
      builder: (_) => Positioned(
        left: position.dx - 4,
        top: position.dy - 40,
        child: Material(
          color: colorTokens.containerL1,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ArDriveSpacing.sm,
              vertical: ArDriveSpacing.xxs,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _copied! ? widget.copiedLabel : widget.copyFailedLabel,
                style: typography.paragraphNormal(
                  color: _copied! ? null : colorTokens.statusErrorFg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final isMasked = widget.isSecret && !_isRevealed;
    final hasRevealSlot = widget.isSecret || widget.alignsWithSecret;

    // The label is drawn above the row rather than by the field: inside it,
    // the row centred Copy on the label and box together, so Copy sat above
    // the middle of the box.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Seen, not heard: the field carries the label for a screen reader,
        // which would otherwise read it twice.
        Padding(
          padding: const EdgeInsets.only(bottom: ArDriveSpacing.xxs),
          child: ExcludeSemantics(
            child: TextFieldLabelNew(
              text: widget.label,
              style: typography.paragraphNormal(
                color: colorTokens.textLow,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: MergeSemantics(
                child: Semantics(
                  label: widget.label,
                  child: ArDriveTextFieldNew(
                    // The field copies obscureText into its state once, so a
                    // new key makes a fresh field when the mask changes. Safe:
                    // it is read only and its value lives on the controller.
                    key: ValueKey(isMasked),
                    controller: _controller,
                    isEnabled: false,
                    obscureText: isMasked,
                    textStyle: widget.isMonospace ? typography.code() : null,
                    // Not the field's own toggle: it sits inside a disabled
                    // field, which swallows the tap, so the mask could never
                    // be lifted.
                    showObfuscationToggle: false,
                  ),
                ),
              ),
            ),
            if (hasRevealSlot) ...[
              const SizedBox(width: ArDriveSpacing.xs),
              SizedBox(
                width: _revealSlotWidth,
                child: widget.isSecret
                    // An IconButton for its keyboard focus and hover tooltip:
                    // the control has no visible label. Its semantics are
                    // declared here instead of the button's, so a screen
                    // reader hears one control that says whether the key is
                    // showing - the name is the same either way.
                    ? Semantics(
                        button: true,
                        toggled: _isRevealed,
                        label: widget.revealLabel,
                        onTap: _toggleReveal,
                        excludeSemantics: true,
                        child: IconButton(
                          icon: isMasked
                              ? ArDriveIcons.eyeClosed(
                                  color: colorTokens.textMid)
                              : ArDriveIcons.eyeOpen(
                                  color: colorTokens.textMid),
                          onPressed: _toggleReveal,
                          tooltip: widget.revealLabel,
                          splashRadius: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: _revealSlotWidth,
                            height: _revealSlotWidth,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
            const SizedBox(width: ArDriveSpacing.sm),
            ArDriveLink(
              key: _copyKey,
              text: widget.copyLabel,
              onTap: _copy,
              isAction: true,
            ),
          ],
        ),
      ],
    );
  }
}
