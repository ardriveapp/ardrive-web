import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/utils/app_url_strategy.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// The origin every share link is rooted at.
///
/// On web, the origin the user is already on - a link copied from a preview
/// build points back at that preview build. Everywhere else, app.ardrive.io.
String shareLinkOrigin() => kIsWeb ? Uri.base.origin : linkOriginProduction;

/// A share link for a public drive, or for one folder inside it.
///
/// The name rides along because a public drive's name is not a secret and it
/// saves the recipient's client a lookup. See [generatePrivateDriveShareLink]
/// for why the private variant carries none.
Uri generatePublicDriveShareLink({
  required final DriveID driveId,
  required final String driveName,
  final FolderID? folderId,
}) {
  final driveShareLink = '${shareLinkOrigin()}'
      '${_driveLocation(driveId: driveId, folderId: folderId)}'
      '?name=${Uri.encodeQueryComponent(driveName)}';

  return Uri.parse(driveShareLink);
}

/// The route location of a drive, or of a folder within it.
String _driveLocation({required DriveID driveId, FolderID? folderId}) =>
    folderId == null
        ? '/#/drives/$driveId'
        : '/#/drives/$driveId/folders/$folderId';

/// A share link for a private drive.
///
/// Deliberately carries no `name`. A private drive's name is a secret of
/// exactly the kind the file link schema added its `hid` flag to protect - a
/// drive called "Q4 Layoffs" leaks whether or not the key sits beside it, and
/// a URL is the least private place a string can live: browser history, the
/// address bar, screenshots, and every unfurl preview.
///
/// Nothing is lost by omitting it. The recipient's attach flow resolves the
/// real name from the drive's own record as soon as the key is in hand
/// (`DriveAttachCubit.driveNameLoader`), so the name in the link was only ever
/// a pre-fill that the chain immediately overwrote.
/// [includeKey] embeds the drive key in the link.
///
/// Off by default, and off is what the share dialog uses unless the sharer
/// opts in. A drive key opens every file and every folder name in the drive
/// for the life of the drive, and - unlike a password - **it cannot be
/// rotated**. A link that carries one is a link whose key is in every forward,
/// screenshot and unfurl of the message it travelled in. The keyless link and
/// the key are handed over as two artifacts, meant for two channels, exactly
/// as a private file's are.
///
/// A recipient who opens a keyless link is not stuck: the attach form asks for
/// the key, validates it, and reads the drive's real name off the chain once
/// it has one.
Future<Uri> generatePrivateDriveShareLink({
  required final DriveID driveId,
  required final SecretKey driveKey,
  final FolderID? folderId,
  final bool includeKey = false,
}) async {
  final location =
      '${shareLinkOrigin()}${_driveLocation(driveId: driveId, folderId: folderId)}';

  if (!includeKey) {
    return Uri.parse(location);
  }

  final driveKeyBase64 = encodeBytesToBase64(await driveKey.extractBytes());

  return Uri.parse('$location?driveKey=$driveKeyBase64');
}

Uri generatePublicFileShareLink({
  required FileID fileId,
  AppUrlStrategy strategy = kAppUrlStrategy,
}) =>
    _appLink(
      buildSharedFileLinkLocation(
        fileId: fileId,
        route: strategy.sharedFileRoute,
      ),
      strategy,
    );

Future<Uri> generatePrivateFileShareLink({
  required FileID fileId,
  required SecretKey fileKey,
  AppUrlStrategy strategy = kAppUrlStrategy,
}) async {
  final fileKeyBase64 = encodeBytesToBase64(await fileKey.extractBytes());

  return _appLink(
    buildSharedFileLinkLocation(
      fileId: fileId,
      rawFileKey: fileKeyBase64,
      route: strategy.sharedFileRoute,
      // On the hash route this is the `?fileKey=` position every v1 link has
      // used; on a path route it is `#k=`, since a path route's query reaches
      // the server.
      keyPlacement: strategy.fileKeyPlacement,
    ),
    strategy,
  );
}

/// Builds a v2 shared file link - the schema of
/// `docs/FILE_SHARING_REDESIGN_PLAN.md` §1.2, on whichever route [strategy]
/// makes canonical.
///
/// [payload] carries everything the link asserts about the file. The key is
/// *not* part of it: it is passed as [rawFileKey] and travels only when the
/// caller passes it. A key that happens to sit on [payload] is stripped, so
/// that the keyless two-artifact handover (decision 4) is what a caller gets
/// by default and embedding is always a deliberate act.
///
/// [keyPlacement] defaults to the only position that is safe under [strategy].
///
/// The name is truncated to [SharedFileLinkPayload.maxNameLength] *characters*
/// here rather than at the call site, since a longer name is dropped wholesale
/// by the parser and a truncated hint beats no hint. The payload truncates
/// again if those characters do not fit in 255 UTF-8 bytes - two different
/// limits, both of them about the same thing, and the encoder is the only place
/// that can know about the second one.
Uri generateFileShareLinkV2({
  required FileID fileId,
  required SharedFileLinkPayload payload,
  String? rawFileKey,
  SharedFileLinkKeyPlacement? keyPlacement,
  AppUrlStrategy strategy = kAppUrlStrategy,
}) {
  final key = rawFileKey == null || rawFileKey.isEmpty ? null : rawFileKey;
  final placement = keyPlacement ?? strategy.fileKeyPlacement;

  // A URL has exactly one fragment, and on the hash route the app has already
  // spent it: everything the router reads lives after that first `#`. Asking
  // for a second one does not fail loudly - `Uri` binds the first `#`, then
  // percent-encodes the inner one on the way out, and the key material ends up
  // glued onto the value of whichever query parameter came last. That is the
  // one place a key must never be, so refuse instead of emitting it.
  //
  // Under path routing the app has *not* spent the fragment, and `#k=` is the
  // only position left that a server never sees (§1.2, §4.1) - so the refusal
  // is conditional on the strategy, not on the placement alone.
  if (key != null &&
      placement == SharedFileLinkKeyPlacement.fragment &&
      strategy == AppUrlStrategy.hash) {
    throw UnsupportedError(
      'A fragment-placed key needs a path route. While the app is served on '
      'the hash route the key travels in the hash query, which is equally '
      'never sent to a server.',
    );
  }

  return _appLink(
    buildSharedFileLinkLocation(
      fileId: fileId,
      payload: _sanitize(payload, keyTravels: key != null),
      rawFileKey: key,
      keyPlacement: placement,
      route: strategy.sharedFileRoute,
    ),
    strategy,
  );
}

/// A route location as it appears in a link: after the `#` of the hash route,
/// or straight on the origin under path routing - which is where the app's
/// router reads it from in each case.
Uri _appLink(String location, AppUrlStrategy strategy) =>
    Uri.parse('${shareLinkOrigin()}${strategy.linkPrefix}$location');

SharedFileLinkPayload _sanitize(
  SharedFileLinkPayload payload, {
  required bool keyTravels,
}) {
  var sanitized = payload;

  final name = payload.name;

  if (name != null && name.length > SharedFileLinkPayload.maxNameLength) {
    sanitized = sanitized.copyWith(name: _truncateName(name));
  }

  if (!keyTravels && payload.key.raw != null) {
    sanitized = sanitized.copyWith(key: SharedFileLinkKey.absent);
  }

  return sanitized;
}

/// Cuts [name] to [SharedFileLinkPayload.maxNameLength] code units without
/// splitting a surrogate pair - half of an emoji is not a file name hint.
String _truncateName(String name) {
  var end = SharedFileLinkPayload.maxNameLength;

  if (_isHighSurrogate(name.codeUnitAt(end - 1))) {
    end -= 1;
  }

  return name.substring(0, end);
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xd800 && codeUnit <= 0xdbff;
