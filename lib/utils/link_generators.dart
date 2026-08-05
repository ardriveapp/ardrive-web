import 'package:ardrive/entities/constants.dart';
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

Uri generatePublicDriveShareLink({
  required final DriveID driveId,
  required final String driveName,
}) {
  final driveShareLink =
      '${shareLinkOrigin()}/#/drives/$driveId?name=${Uri.encodeQueryComponent(driveName)}';
  return Uri.parse(driveShareLink);
}

Future<Uri> generatePrivateDriveShareLink({
  required final DriveID driveId,
  required final String driveName,
  required final SecretKey driveKey,
}) async {
  final driveKeyBase64 = encodeBytesToBase64(await driveKey.extractBytes());

  return Uri.parse(
    '${generatePublicDriveShareLink(driveName: driveName, driveId: driveId)}&driveKey=$driveKeyBase64',
  );
}

Uri generatePublicFileShareLink({
  required FileID fileId,
}) =>
    _hashRouteLink(buildSharedFileLinkLocation(fileId: fileId));

Future<Uri> generatePrivateFileShareLink({
  required FileID fileId,
  required SecretKey fileKey,
}) async {
  final fileKeyBase64 = encodeBytesToBase64(await fileKey.extractBytes());

  return _hashRouteLink(
    buildSharedFileLinkLocation(fileId: fileId, rawFileKey: fileKeyBase64),
  );
}

/// Builds a v2 shared file link - the schema of
/// `docs/FILE_SHARING_REDESIGN_PLAN.md` §1.2, on the Phase 1 hash route.
///
/// [payload] carries everything the link asserts about the file. The key is
/// *not* part of it: it is passed as [rawFileKey] and travels only when the
/// caller passes it. A key that happens to sit on [payload] is stripped, so
/// that the keyless two-artifact handover (decision 4) is what a caller gets
/// by default and embedding is always a deliberate act.
///
/// The name is truncated to [SharedFileLinkPayload.maxNameLength] here rather
/// than at the call site, since a longer name is dropped wholesale by the
/// parser and a truncated hint beats no hint.
Uri generateFileShareLinkV2({
  required FileID fileId,
  required SharedFileLinkPayload payload,
  String? rawFileKey,
  SharedFileLinkKeyPlacement keyPlacement =
      SharedFileLinkKeyPlacement.hashQuery,
}) {
  final key = rawFileKey == null || rawFileKey.isEmpty ? null : rawFileKey;

  // A URL has exactly one fragment, and on the hash route the app has already
  // spent it: everything the router reads lives after that first `#`. Asking
  // for a second one does not fail loudly - `Uri` binds the first `#`, then
  // percent-encodes the inner one on the way out, and the key material ends up
  // glued onto the value of whichever query parameter came last. That is the
  // one place a key must never be, so refuse instead of emitting it.
  //
  // Fragment placement becomes real with the path routes of Phase 3
  // (`docs/FILE_SHARING_REDESIGN_PLAN.md` §4.1); `buildSharedFileLinkLocation`
  // already supports it, and only this hash-route composition cannot.
  if (key != null && keyPlacement == SharedFileLinkKeyPlacement.fragment) {
    throw UnsupportedError(
      'A fragment-placed key needs a path route. While the app is served on '
      'the hash route the key travels in the hash query, which is equally '
      'never sent to a server.',
    );
  }

  return _hashRouteLink(
    buildSharedFileLinkLocation(
      fileId: fileId,
      payload: _sanitize(payload, keyTravels: key != null),
      rawFileKey: key,
      keyPlacement: keyPlacement,
    ),
  );
}

/// A route location as it appears in a link: after the `#` of the hash route,
/// which is where the app's router reads it from.
Uri _hashRouteLink(String location) =>
    Uri.parse('${shareLinkOrigin()}/#$location');

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
