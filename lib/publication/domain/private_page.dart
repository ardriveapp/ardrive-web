import 'dart:math';
import 'dart:typed_data';

import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/publication/domain/sealed/seal_codec.dart';
import 'package:ardrive/publication/domain/sealed/sealing.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;

/// What a private drive or folder page (publication.json version 3) carries
/// beyond a public page's look: its catalog, the keys that open it, and the
/// slots that give the publication key back (docs/ArweaveFS.md, "Private
/// publications"). Made once per publish dialog; secrets stay in memory.
class PrivatePagePlan {
  PrivatePagePlan({
    required this.catalog,
    required this.catalogKey,
    required this.publicationKey,
    required this.slots,
    required this.fileKeys,
    required this.rootFolderId,
  });

  /// The page's scope as a Drive State, sealed under [catalogKey].
  final PreparedDriveStateArtifact catalog;
  final Uint8List catalogKey;

  /// The same for every version of the page.
  final Uint8List publicationKey;

  /// As written into publication.json: an owner slot, and a password slot
  /// when the page has one.
  final List<Map<String, Object>> slots;

  /// File ID to its key, base64url, for every file in [catalog].
  final Map<String, String> fileKeys;

  /// The drive's root folder, which the sealed block names.
  final String rootFolderId;

  bool get hasPassword => slots.any((s) => s['type'] == 'password');

  /// The page link's key: `#/?k=<this>`.
  String get linkKey => b64u(publicationKey);

  /// The tags an importer reads, for the sealed block's `catalog.tags`.
  Map<String, String> get catalogTags => importTagsOf(catalog.entity);

  /// The sealed block, given the transaction the catalog was signed as
  /// (docs/ArweaveFS.md, "The sealed block"). `ciphers` is left empty: a
  /// reader looks a transaction's cipher up as usual when it is missing.
  Map<String, Object?> sealedBlock({
    required Map<String, Object?> scope,
    required String catalogTxId,
  }) =>
      {
        'v': sealedVersion,
        'scope': scope,
        'rootFolderId': rootFolderId,
        'catalog': {
          'path': 'catalog',
          'txId': catalogTxId,
          'key': b64u(catalogKey),
          'tags': catalogTags,
        },
        'files': fileKeys,
        'ciphers': const <String, Object>{},
      };
}

/// The tags [entity] is published with, as a map.
Map<String, String> importTagsOf(DriveStateEntity entity) {
  final item = DataItem.withBlobData(data: Uint8List(0));
  entity.addEntityTagsToTransaction(item);
  return {
    for (final tag in item.tags)
      utils.decodeBase64ToString(tag.name):
          utils.decodeBase64ToString(tag.value),
  };
}

/// [count] random bytes, from the platform's secure source.
Uint8List secureRandomBytes(int count) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(count, (_) => random.nextInt(256)));
}

/// The publication key a page's owner slot gives back to [driveKey], or null
/// when it has no owner slot or the key doesn't open it. [settings] is the
/// page's publication.json as read.
Future<Uint8List?> ownerPublicationKey(
  Map<String, dynamic> settings,
  List<int> driveKey, {
  Sealing? sealing,
}) async {
  final page = readPrivatePublication(settings);
  final slot = page.ownerSlot;
  if (slot == null) return null;
  final seal = sealing ?? Sealing();
  try {
    final kek = await seal.ownerKek(driveKey, page.publicationId);
    return await seal.unwrapKey(kek, slot.iv, slot.wrapped, page.publicationId);
  } on SealError catch (e) {
    if (e.code == SealErrorCode.noMatch) return null;
    rethrow;
  }
}

/// The slots of a page's next version. An update carries [previous] forward
/// as it was, adding a password slot only when it has none: access is never
/// taken back, so a password is never changed or removed. A first version
/// gets an owner slot and, with [password], a password slot.
Future<List<Map<String, Object>>> pageSlots({
  required Uint8List publicationKey,
  required String publicationId,
  required List<int> driveKey,
  List<Map<String, Object>>? previous,
  String? password,
  Sealing? sealing,
  Argon2Settings settings = argon2Defaults,
}) async {
  final seal = sealing ?? Sealing();
  final slots = previous != null
      ? [...previous]
      : [
          await seal.ownerSlot(
            driveKey: driveKey,
            iv: secureRandomBytes(ivBytes),
            publicationKey: publicationKey,
            publicationId: publicationId,
          ),
        ];
  final hasPassword = slots.any((s) => s['type'] == 'password');
  if (password != null && password.isNotEmpty && !hasPassword) {
    slots.add(await seal.passwordSlot(
      password: password,
      salt: secureRandomBytes(argon2SaltBytesBounds.$1),
      iv: secureRandomBytes(ivBytes),
      settings: settings,
      publicationKey: publicationKey,
      publicationId: publicationId,
    ));
  }
  return slots;
}

/// A previous version's slots, as its publication.json had them.
List<Map<String, Object>> slotsOf(Map<String, dynamic> settings) => [
      for (final slot in settings['slots'] as List? ?? const [])
        if (slot is Map) Map<String, Object>.from(slot),
    ];
