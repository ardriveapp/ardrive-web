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
