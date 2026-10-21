import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/pages/app_route_information_parser.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

/// What somebody pasted into the "Open a drive" field, read the way the
/// address bar would read it.
///
/// One field takes a Drive ID or any ArDrive link, because people have links
/// far more often than IDs. The link vocabulary - every route shape and every
/// key spelling - already lives in [AppRouteInformationParser], so this hands
/// the pasted text to it rather than growing a second grammar that would drift
/// from the first.
sealed class DriveLinkInput {
  const DriveLinkInput();

  /// Reads [raw]. Never throws: text that is not a drive, a file or a
  /// transaction comes back as [DriveLinkInputUnrecognised].
  static Future<DriveLinkInput> parse(
    String raw, {
    AppRouteInformationParser? parser,
  }) async {
    final text = raw.trim();

    if (text.isEmpty) {
      return const DriveLinkInputUnrecognised();
    }

    if (isBareDriveId(text)) {
      return DriveLinkInputDrive(driveId: text);
    }

    final location = _routeLocation(text);

    if (location == null) {
      return const DriveLinkInputUnrecognised();
    }

    final route = await (parser ?? AppRouteInformationParser())
        .parseRouteInformation(RouteInformation(uri: Uri.parse(location)));

    if (route.driveId != null && !route.drivesList) {
      return DriveLinkInputDrive(
        driveId: route.driveId!,
        folderId: route.driveFolderId,
        driveKey: route.sharedDriveKey,
        rawDriveKey: route.sharedRawDriveKey,
      );
    }

    if (route.sharedFileId != null || route.rawTransactionId != null) {
      return DriveLinkInputOtherLink(route);
    }

    return const DriveLinkInputUnrecognised();
  }

  /// A Drive ID on its own: the UUID ArFS assigns, or the 43 character
  /// base64url form a few tools print.
  static bool isBareDriveId(String text) =>
      Uuid.isValidUUID(fromString: text) || isCanonical32ByteId(text);

  /// The route inside a pasted link, whatever was around it.
  ///
  /// The app runs on the hash URL strategy, so a copied link reads
  /// `https://app.ardrive.io/#/drives/{id}?driveKey=…` and the route is the
  /// fragment. A link copied from a path-routed host, or typed by hand as
  /// `/drives/{id}`, carries it in the path instead. Both land here.
  static String? _routeLocation(String text) {
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }

    if (uri.hasFragment && uri.fragment.startsWith('/')) {
      return uri.fragment;
    }

    if (uri.path.isEmpty || uri.path == '/') {
      return null;
    }

    // `app.ardrive.io/drives/{id}` without a scheme parses as a path whose
    // first segment is the host. The parser knows its route segments; a host
    // in front of one is dropped so the route is what gets read.
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.first.contains('.')) {
      segments.removeAt(0);
    }

    if (segments.isEmpty) {
      return null;
    }

    final path = '/${segments.join('/')}';
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }
}

/// A drive, with the folder and key the link carried if it carried them.
class DriveLinkInputDrive extends DriveLinkInput {
  const DriveLinkInputDrive({
    required this.driveId,
    this.folderId,
    this.driveKey,
    this.rawDriveKey,
  });

  final String driveId;
  final String? folderId;
  final DriveKey? driveKey;
  final String? rawDriveKey;
}

/// A shared file or a raw transaction: pages the app already shows a visitor,
/// reached by handing the route straight to the router.
class DriveLinkInputOtherLink extends DriveLinkInput {
  const DriveLinkInputOtherLink(this.route);

  final AppRoutePath route;

  bool get isFile => route.sharedFileId != null;
}

/// Neither an ID nor a link the app knows.
class DriveLinkInputUnrecognised extends DriveLinkInput {
  const DriveLinkInputUnrecognised();
}
