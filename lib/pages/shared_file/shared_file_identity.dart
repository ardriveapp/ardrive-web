import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArDriveIcons.triangle(size: 16, color: colors.themeWarningFg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  appLocalizationsOf(context).sharedFileLinkDetailsMismatch,
                  style: ArDriveTypography.body.captionRegular(
                    color: colors.themeWarningFg,
                  ),
                ),
              ),
            ],
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

    return Text(
      name ??
          (isPrivate
              ? appLocalizationsOf(context).sharedFileEncryptedFileTitle
              : appLocalizationsOf(context).sharedFileGenericTitle),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: ArDriveTypography.headline.headline5Bold(
        color: colors.themeFgDefault,
      ),
    );
  }

  Widget _buildMeta(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final style = ArDriveTypography.body.captionRegular(
      color: colors.themeFgSubtle,
    );

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

    final ownerAddress = this.ownerAddress;

    if (ownerAddress != null && ownerAddress.isNotEmpty) {
      parts.add(
        Row(
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
        ),
      );
    }

    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    // A wrap, not a row: on a narrow phone the sender line drops to its own
    // line instead of ellipsing the size away.
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0)
            Text(
              '·',
              style: style,
            ),
          parts[i],
        ],
      ],
    );
  }

  Widget _buildLeading(BuildContext context) {
    final thumbnailTxId = this.thumbnailTxId;
    final icon = getIconForContentType(
      contentType ?? 'application/octet-stream',
      size: 24,
    );
    final gatewayUrl = thumbnailTxId == null ? null : _gatewayUrl(context);

    if (thumbnailTxId == null || gatewayUrl == null) {
      return SizedBox(width: 44, height: 44, child: Center(child: icon));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Image.network(
          '$gatewayUrl/$thumbnailTxId',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Center(child: icon),
        ),
      ),
    );
  }

  /// The gateway the thumbnail can be fetched from, or `null` when this page
  /// is rendered without the app's service tree (widget tests, and later the
  /// standalone viewer). A missing gateway costs a thumbnail, never the page.
  String? _gatewayUrl(BuildContext context) {
    try {
      return '${context.read<ArweaveService>().client.api.gatewayUrl}';
    } catch (_) {
      return null;
    }
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
class SharedFileVerificationBadge extends StatelessWidget {
  const SharedFileVerificationBadge({super.key, required this.verification});

  final LinkVerification verification;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    if (verification == LinkVerification.verified) {
      return _badge(
        context,
        icon: ArDriveIcons.checkCirle(
          size: 14,
          color: colors.themeSuccessDefault,
        ),
        label: appLocalizationsOf(context).sharedFileLinkVerified,
        color: colors.themeSuccessDefault,
      );
    }

    if (verification == LinkVerification.mismatch) {
      return _badge(
        context,
        icon: ArDriveIcons.triangle(size: 14, color: colors.themeWarningFg),
        label: appLocalizationsOf(context).sharedFileLinkDetailsMismatch,
        color: colors.themeWarningFg,
      );
    }

    if (verification == LinkVerification.pending) {
      return _badge(
        context,
        icon: null,
        label: appLocalizationsOf(context).sharedFileLinkChecking,
        color: colors.themeFgSubtle,
      );
    }

    // Unavailable - and anything a later verification step adds. A check that
    // did not run is never reported as a problem with the file.
    return _badge(
      context,
      icon: null,
      label: appLocalizationsOf(context).sharedFileLinkNotChecked,
      color: colors.themeFgSubtle,
    );
  }

  Widget _badge(
    BuildContext context, {
    required Widget? icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          icon,
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: ArDriveTypography.body.captionRegular(color: color),
        ),
      ],
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
