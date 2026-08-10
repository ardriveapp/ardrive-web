import 'package:ardrive/utils/shared_file_link.dart';

// The generalized raw-transaction viewer's link shape - see
// `docs/FILE_SHARING_REDESIGN_PLAN.md` §1.3 and §4.3.
//
// `/view/{txId}` takes an Arweave transaction id and, optionally, the same
// `n` (file name) and `ct` (content type) hints the shared file schema uses -
// the field names, the validation and the "absent ⇒ client behavior" rules are
// shared with §1.2 rather than reinvented here.
//
// v1 of the route serves public content only: no `c`/`iv`/`k`, so an encrypted
// blob with no ArFS context renders as the download-only card.

/// The first path segment of the raw transaction route.
const rawTransactionRouteSegment = 'view';

/// The route location of `/view/{txId}`, with whatever hints are worth
/// carrying.
///
/// Both hints are validated on the way out with the same rules that will be
/// applied on the way in, so a hint that would be dropped by the parser is
/// never written in the first place. Values are percent-encoded.
String buildRawTransactionViewLocation({
  required String txId,
  String? name,
  String? contentType,
}) {
  final parameters = <String, String>{};

  final sanitizedName = SharedFileLinkPayload.sanitizeName(name);

  if (sanitizedName != null) {
    parameters[SharedFileLinkParams.name] = sanitizedName;
  }

  final sanitizedContentType =
      SharedFileLinkPayload.sanitizeContentType(contentType);

  if (sanitizedContentType != null) {
    parameters[SharedFileLinkParams.contentType] = sanitizedContentType;
  }

  final path = '/$rawTransactionRouteSegment/$txId';

  if (parameters.isEmpty) {
    return path;
  }

  final query = parameters.entries
      .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
      .join('&');

  return '$path?$query';
}
