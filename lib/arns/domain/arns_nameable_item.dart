import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:equatable/equatable.dart';

/// Where a name opens in a browser: `blog_ardrive.ar.io`.
const arnsLinkHost = 'ar.io';

/// The console, for buying, renewing and ownership (docs/NAMES.md, Q1).
const arnsConsoleUrl = 'https://console.ar.io';

/// The console's page for one name, where it is renewed.
String arnsRenewUrlFor(String name) =>
    '$arnsConsoleUrl/domains/${Uri.encodeComponent(name)}';

/// The console's ArNS page, where names are searched and bought.
const arnsGetNameUrl = '$arnsConsoleUrl/arns';

/// What a name is, for people new to ArNS.
const arnsDocsUrl = 'https://docs.ar.io/learn/arns';

/// `blog_ardrive.ar.io` for a literal name.
String arnsHostFor(String literalName) => '$literalName.$arnsLinkHost';

String arnsUrlFor(String literalName) => 'https://${arnsHostFor(literalName)}';

/// A file that can be given a name: a public file or a deployment, never a
/// private file (docs/NAMES.md, Q5). Publications come with the name step in
/// Publish.
class ArNSNameableItem extends Equatable {
  const ArNSNameableItem({
    required this.fileId,
    required this.driveId,
    required this.name,
    required this.dataTxId,
    required this.isManifest,
    this.isPublication = false,
  });

  /// A publication, which keeps its names in `publication.json` rather than
  /// in file metadata. [fileId] is its publication ID.
  const ArNSNameableItem.publication({
    required String publicationId,
    required this.driveId,
    required this.name,
    required this.dataTxId,
  })  : fileId = publicationId,
        isManifest = true,
        isPublication = true;

  final String fileId;
  final String driveId;
  final String name;

  /// What a name pointing here opens.
  final String dataTxId;
  final bool isManifest;
  final bool isPublication;

  @override
  List<Object?> get props =>
      [fileId, driveId, name, dataTxId, isManifest, isPublication];
}

/// Whether a file can be named here: the owner's file in a public drive.
bool isArNSNameable({
  required bool namesEnabled,
  required bool driveIsPublic,
  required bool isOwner,
}) =>
    namesEnabled && driveIsPublic && isOwner;

/// The records among [names] that point at [dataTxId], name first.
List<ArNSNameRecord> recordsPointingAt(
  List<ArNSManagedName> names,
  String dataTxId,
) =>
    [
      for (final name in names)
        for (final record in name.records)
          if (record.transactionId == dataTxId) record,
    ];

/// Credits from winc, for the cost line: never "free", never 0 when it isn't,
/// and rounded up, so the cost said before the prompt is never less than
/// what is debited. Four decimals under one credit, two from one up.
String formatArNSCredits(BigInt winc) {
  if (winc <= BigInt.zero) return '0';
  final minimum = BigInt.from(10).pow(8); // 0.0001
  if (winc < minimum) return '< 0.0001';
  final four = _creditsRoundedUp(winc, 4);
  return four.startsWith('0.') ? four : _creditsRoundedUp(winc, 2);
}

String _creditsRoundedUp(BigInt winc, int places) {
  final scale = BigInt.from(10).pow(places);
  final step = BigInt.from(10).pow(12) ~/ scale;
  final units = (winc + step - BigInt.one) ~/ step;
  final fraction = (units % scale).toString().padLeft(places, '0');
  return '${units ~/ scale}.$fraction';
}

/// SOL from lamports, to two significant digits: "0.000005", "0.0031".
String formatSol(int lamports) {
  if (lamports <= 0) return '0';
  final sol = lamports / 1e9;
  var decimals = 2;
  while (decimals < 9 && sol < 1 / _pow10(decimals - 1)) {
    decimals++;
  }
  return sol
      .toStringAsFixed(decimals)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

double _pow10(int n) {
  var v = 1.0;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}
