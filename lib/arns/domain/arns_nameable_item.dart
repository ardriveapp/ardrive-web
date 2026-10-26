import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:equatable/equatable.dart';

/// Where a name opens in a browser: `blog_ardrive.ar.io`.
const arnsLinkHost = 'ar.io';

/// The console, for buying, renewing and ownership (docs/NAMES.md, Q1).
const arnsConsoleUrl = 'https://console.ar.io';

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

/// Credits from winc, for the cost line: never "free", never 0 when it isn't.
String formatArNSCredits(BigInt winc) {
  final divisor = BigInt.from(10).pow(12);
  if (winc <= BigInt.zero) return '0';
  final minimum = BigInt.from(10).pow(8); // 0.0001
  if (winc < minimum) return '< 0.0001';
  final whole = winc ~/ divisor;
  final fraction = (winc % divisor) * BigInt.from(10000) ~/ divisor;
  final digits = fraction.toString().padLeft(4, '0');
  if (whole >= BigInt.one) {
    return '$whole.${digits.substring(0, 2)}';
  }
  return '0.$digits';
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
