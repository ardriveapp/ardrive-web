import 'package:ardrive/pages/shared_file/shared_file_identity.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The locked gate: the first thing most recipients of a private file see.
///
/// Now that the key travels out of band by default, this is not an error
/// state - it is the normal front door, and it reads like one. It says what is
/// behind the door (when the link embedded the file's details), where the key
/// comes from, and what to do next.
///
/// Two rules hold here:
///
/// 1. A key that cannot possibly work is rejected locally, before any crypto
///    or any network call, by [SharedFileLinkKey.isWellFormed]. A truncated
///    paste is answered instantly.
/// 2. A key that was tried and failed leaves the recipient exactly where they
///    were - same page, same text in the field, an error underneath it. Never
///    a modal, never "the file does not exist".
class SharedFileLockedView extends StatefulWidget {
  const SharedFileLockedView({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.payload,
    this.errorMessage,
    this.rememberKey = false,
    this.onRememberChanged,
    this.isBusy = false,
  });

  /// Owned by the page, not by this widget: the gate is torn down and rebuilt
  /// while a key is being checked, and the recipient's typing has to survive
  /// that.
  final TextEditingController controller;

  final void Function(String rawKey) onSubmit;

  /// What the link told us about the file, if anything.
  final SharedFileLinkPayload? payload;

  /// The error the *cubit* reported - a key that decoded but did not decrypt,
  /// or a link whose key never arrived intact.
  final String? errorMessage;

  final bool rememberKey;
  final ValueChanged<bool>? onRememberChanged;

  /// Whether a submitted key is currently being checked.
  final bool isBusy;

  @override
  State<SharedFileLockedView> createState() => _SharedFileLockedViewState();
}

class _SharedFileLockedViewState extends State<SharedFileLockedView> {
  /// Set by the local shape check, and therefore never the result of a network
  /// round trip.
  String? _shapeError;

  int _previousLength = 0;

  @override
  void initState() {
    super.initState();
    _previousLength = widget.controller.text.length;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final payload = widget.payload;
    final detailsAreHidden = payload?.detailsAreHidden ?? false;
    final showEmbeddedDetails = payload != null && !detailsAreHidden;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SharedFileIdentity(
          name: showEmbeddedDetails ? payload.name : null,
          size: showEmbeddedDetails ? payload.size : null,
          contentType: showEmbeddedDetails ? payload.contentType : null,
          isPrivate: true,
        ),
        if (detailsAreHidden) ...[
          const SizedBox(height: 12),
          Text(
            appLocalizationsOf(context).sharedFileDetailsHiddenBySender,
            style: ArDriveTypography.body.captionRegular(
              color: colors.themeFgSubtle,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          appLocalizationsOf(context).sharedFileProtectedWithAccessKey,
          style: ArDriveTypography.body.bodyBold(
            color: colors.themeFgDefault,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          appLocalizationsOf(context).sharedFileAccessKeySentSeparately,
          style: ArDriveTypography.body.captionRegular(
            color: colors.themeFgSubtle,
          ),
        ),
        const SizedBox(height: 16),
        ArDriveTextField(
          controller: widget.controller,
          autofocus: true,
          autocorrect: false,
          obscureText: true,
          showObfuscationToggle: true,
          isEnabled: !widget.isBusy,
          hintText: appLocalizationsOf(context).sharedFilePasteAccessKey,
          errorMessage: _shapeError ?? widget.errorMessage,
          onChanged: _onChanged,
          onFieldSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        ArDriveCheckBox(
          // [ArDriveCheckBox] reads `checked` once, in its own initState, so
          // the key is what lets the page drive it - it is ticked for the
          // recipient when a remembered key is restored.
          key: ValueKey(widget.rememberKey),
          title: appLocalizationsOf(context).sharedFileRememberKeyForThisTab,
          checked: widget.rememberKey,
          onChange: (value) => widget.onRememberChanged?.call(value),
          titleStyle: ArDriveTypography.body.captionRegular(
            color: colors.themeFgSubtle,
          ),
        ),
        const SizedBox(height: 16),
        ArDriveButton(
          maxWidth: double.infinity,
          isDisabled: widget.isBusy || widget.controller.text.trim().isEmpty,
          onPressed: _submit,
          text: appLocalizationsOf(context).sharedFileUnlockFile,
        ),
        if (widget.isBusy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 12),
        Text(
          appLocalizationsOf(context).sharedFileAccessKeyStaysOnThisDevice,
          textAlign: TextAlign.center,
          style: ArDriveTypography.body.captionRegular(
            color: colors.themeFgSubtle,
          ),
        ),
      ],
    );
  }

  void _onChanged(String value) {
    final grewByMoreThanOneCharacter = value.length - _previousLength > 1;

    _previousLength = value.length;

    setState(() {
      // Typing clears the local complaint; the cubit's error stays until the
      // next attempt actually resolves.
      _shapeError = null;
    });

    // Paste-first: a whole key arriving at once is the common case, and it is
    // an unambiguous signal to just try it.
    if (grewByMoreThanOneCharacter &&
        SharedFileLinkKey.isWellFormed(value.trim())) {
      _submit();
    }
  }

  void _submit() {
    if (widget.isBusy) {
      return;
    }

    final rawKey = widget.controller.text.trim();

    if (rawKey.isEmpty) {
      return;
    }

    // The shape check is the whole point of this branch: a mistyped or
    // truncated key fails here, in microseconds, with the field untouched.
    if (!SharedFileLinkKey.isWellFormed(rawKey)) {
      setState(() {
        _shapeError = appLocalizationsOf(context).sharedFileAccessKeyMalformed;
      });

      return;
    }

    setState(() {
      _shapeError = null;
    });

    widget.onSubmit(rawKey);
  }
}
