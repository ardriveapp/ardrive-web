import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/shared_file/shared_file_colors.dart';
import 'package:ardrive/pages/shared_file/shared_file_thumbnail.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

/// Who and what this link points at, in the recipient's language.
///
/// The same block renders in three states, because the recipient should
/// recognise the file before, during and after resolution: locked (name and
/// size only when the link embedded them), loading (skeleton where a value has
/// not arrived) and ready (name, size, type, sender and verification badge).
///
/// Nothing technical belongs here. Transaction ids live in the details drawer
/// of the ready card, one deliberate tap away.
class SharedFileIdentity extends StatelessWidget {
  const SharedFileIdentity({
    super.key,
    this.name,
    this.size,
    this.contentType,
    this.thumbnailTxId,
    this.fileKey,
    this.thumbnailLoader,
    this.ownerAddress,
    this.verification,
    this.isPrivate = false,
    this.isLoading = false,
  });

  /// The file name, or `null` when the link did not carry one and metadata has
  /// not resolved yet.
  final String? name;

  /// The file size in bytes, when it is known.
  final int? size;

  final String? contentType;

  /// `thn` - the file's thumbnail, shown in place of the type icon.
  final String? thumbnailTxId;

  /// The recipient's access key, which a private file's thumbnail is encrypted
  /// under just as the file is. `null` on every state that has no key, and
  /// nothing is fetched for a private thumbnail without one.
  final SecretKey? fileKey;

  /// Injectable for tests; otherwise built from the service tree.
  final SharedFileThumbnailLoader? thumbnailLoader;

  /// The address the file was shared by.
  final String? ownerAddress;

  /// How the link's claims compare to the file's own record. `null` on the
  /// states that have not checked (locked, loading).
  final LinkVerification? verification;

  /// Tunes the fallback title: an unlocked file is a "Shared file", a locked
  /// one is an "Encrypted file".
  final bool isPrivate;

  /// Renders a placeholder wherever a value is still missing.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final mismatch = verification == LinkVerification.mismatch;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLeading(context),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitle(context),
                  const SizedBox(height: 6),
                  _buildMeta(context),
                ],
              ),
            ),
          ],
        ),
        if (mismatch) ...[
          const SizedBox(height: 12),
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The colour is the cue, the sentence is the message. The
                // warning yellow clears 3:1 on both surfaces as a *graphic*,
                // but not the 4.5:1 that caption text needs on the light
                // theme, so the sentence itself is the default foreground.
                ExcludeSemantics(
                  child: ArDriveIcons.triangle(
                    size: 16,
                    color: colors.themeWarningFg,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appLocalizationsOf(context).sharedFileLinkDetailsMismatch,
                    style: ArDriveTypography.body.captionRegular(
                      color: colors.themeFgDefault,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTitle(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final name = this.name;

    if (name == null && isLoading) {
      return const _SharedFileSkeletonBar(width: 180, height: 20);
    }

    // The one heading on the page, and the thing a screen reader user is here
    // for: what am I being given?
    return Semantics(
      header: true,
      child: Text(
        name ??
            (isPrivate
                ? appLocalizationsOf(context).sharedFileEncryptedFileTitle
                : appLocalizationsOf(context).sharedFileGenericTitle),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        // `heading5` from the newer scale, not `headline.headline5Bold` from
        // the legacy one. The legacy style is 22px at w800 - the heaviest
        // weight in the system - and is what `ardrive_ui` gives button labels
        // and modal titles, so the file name was set exactly as heavy as the
        // Download button directly beneath it and won a shouting match with
        // it. 20px at w700 still reads as the page's one heading without
        // competing with the primary action, and it is the scale
        // `details_panel.dart` uses, which is the surface this page replaced.
        style: ArDriveTypographyNew.of(context).heading5(
          color: colors.themeFgDefault,
          fontWeight: ArFontWeight.bold,
        ),
      ),
    );
  }

  /// What the file is, and who it came from.
  ///
  /// Two lines, not one wrapping list. The first says what the file is - a
  /// size and a type, both short, both about the bytes. The second says where
  /// it came from, and whether the link's claim about that held up.
  ///
  /// The two used to be one [Wrap] of dot-separated items, which put a
  /// separator in the wrap in its own right: when the sender dropped to the
  /// next line the dot it belonged to stayed behind, and the card read
  /// `4.60 MiB · PDF ·`, pointing at nothing. Separators now travel with the
  /// item they introduce, and the one place that reliably wrapped is not a
  /// wrap any more.
  Widget _buildMeta(BuildContext context) {
    final style = ArDriveTypography.body.captionRegular(
      color: SharedFileColors.subtle(context),
    );

    final facts = _buildFacts(context, style);
    final provenance = _buildProvenance(context, style);

    if (facts == null && provenance == null) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (facts != null) facts,
        if (facts != null && provenance != null) const SizedBox(height: 4),
        if (provenance != null) provenance,
      ],
    );
  }

  /// The size and the type, or `null` when neither is known yet.
  Widget? _buildFacts(BuildContext context, TextStyle style) {
    final parts = <Widget>[];

    if (size != null) {
      parts.add(Text(filesize(size), style: style));
    } else if (isLoading) {
      parts.add(const _SharedFileSkeletonBar(width: 64, height: 12));
    }

    final typeLabel = _typeLabel();

    if (typeLabel != null) {
      parts.add(Text(typeLabel, style: style));
    }

    if (parts.isEmpty) {
      return null;
    }

    // Still a wrap rather than a row, and the separator is part of the item
    // after it, so a narrow enough card breaks the line without stranding a
    // dot at the end of it.
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++)
          if (i == 0)
            parts[i]
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('·', style: style),
                const SizedBox(width: 8),
                Flexible(child: parts[i]),
              ],
            ),
      ],
    );
  }

  /// Who shared the file, and how the link's claims about it checked out.
  Widget? _buildProvenance(BuildContext context, TextStyle style) {
    final ownerAddress = this.ownerAddress;

    if (ownerAddress == null || ownerAddress.isEmpty) {
      return null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            appLocalizationsOf(context)
                .sharedFileSharedBy(_shortAddress(ownerAddress)),
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (verification != null &&
            verification != LinkVerification.mismatch) ...[
          const SizedBox(width: 6),
          SharedFileVerificationBadge(verification: verification!),
        ],
      ],
    );
  }

  Widget _buildLeading(BuildContext context) {
    final thumbnailTxId = this.thumbnailTxId;

    // Decorative in both places it is used: the file's type is already written
    // out in words in the meta line, so reading the icon out as well would only
    // say it twice.
    final icon = ExcludeSemantics(
      child: getIconForContentType(
        contentType ?? 'application/octet-stream',
        size: 24,
      ),
    );

    if (thumbnailTxId == null) {
      return SizedBox(width: 44, height: 44, child: Center(child: icon));
    }

    return SharedFileThumbnail(
      txId: thumbnailTxId,
      fallback: icon,
      // The picture is of the file, so the file's own name is what it is a
      // picture of. Falls back to nothing rather than to a label that says
      // "image": an unnamed thumbnail is decoration.
      semanticLabel: name,
      // A private file's thumbnail is encrypted under the same key as the file
      // itself, so it renders once the recipient has unlocked the page and not
      // before. Without a key nothing is even requested.
      isPrivate: isPrivate,
      fileKey: fileKey,
      loader: thumbnailLoader,
    );
  }

  /// `application/pdf` reads as `PDF`, `image/jpeg` as `JPEG`. The MIME type
  /// itself is never shown: it is a developer's label, not a recipient's.
  String? _typeLabel() {
    final contentType = this.contentType;

    if (contentType == null || contentType.isEmpty) {
      return null;
    }

    final subtype = contentType.split('/').last.split(';').first.trim();

    if (subtype.isEmpty) {
      return null;
    }

    final withoutVendorPrefix = subtype.startsWith('x-')
        ? subtype.substring(2)
        : subtype.startsWith('vnd.')
            ? subtype.split('.').last
            : subtype;

    return withoutVendorPrefix.length > 8
        ? withoutVendorPrefix.toUpperCase().substring(0, 8)
        : withoutVendorPrefix.toUpperCase();
  }

  String _shortAddress(String address) => address.length <= 13
      ? address
      : '${address.substring(0, 6)}...${address.substring(address.length - 5)}';
}

/// The verification badge that sits beside `Shared by`.
///
/// Only [LinkVerification.verified] is ever affirmative. Pending and
/// unavailable read as neutral - a recipient must not be told that something
/// is wrong when all that happened is that a check has not finished, or that
/// the link carried nothing to check against.
///
/// The state is never carried by the tick and the colour alone: every one of
/// these has a word next to it, and that word is what a screen reader is given
/// - the icon beside it is excluded so that the badge reads once, as one thing.
class SharedFileVerificationBadge extends StatelessWidget {
  const SharedFileVerificationBadge({super.key, required this.verification});

  final LinkVerification verification;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    if (verification == LinkVerification.verified) {
      // `themeSuccessDefault` is `green.400` in both themes and reads at
      // ~2.2:1 on the light card, so the badge takes the token that passes.
      final color = SharedFileColors.success(context);

      return _badge(
        context,
        icon: ArDriveIcons.checkCirle(size: 14, color: color),
        label: appLocalizationsOf(context).sharedFileLinkVerified,
        color: color,
      );
    }

    if (verification == LinkVerification.mismatch) {
      return _badge(
        context,
        icon: ArDriveIcons.triangle(size: 14, color: colors.themeWarningFg),
        label: appLocalizationsOf(context).sharedFileLinkDetailsMismatch,
        color: colors.themeFgDefault,
      );
    }

    if (verification == LinkVerification.pending) {
      return _badge(
        context,
        icon: null,
        label: appLocalizationsOf(context).sharedFileLinkChecking,
        color: SharedFileColors.subtle(context),
      );
    }

    // Unavailable - and anything a later verification step adds. A check that
    // did not run is never reported as a problem with the file.
    return _badge(
      context,
      icon: null,
      label: appLocalizationsOf(context).sharedFileLinkNotChecked,
      color: SharedFileColors.subtle(context),
    );
  }

  Widget _badge(
    BuildContext context, {
    required Widget? icon,
    required String label,
    required Color color,
  }) {
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            ExcludeSemantics(child: icon),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: ArDriveTypography.body.captionRegular(color: color),
          ),
        ],
      ),
    );
  }
}

class _SharedFileSkeletonBar extends StatelessWidget {
  const _SharedFileSkeletonBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ArDriveTheme.of(context).themeData.colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
