import 'dart:typed_data';

import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:test/test.dart';

/// The one version this build writes and reads. Tests follow the constant
/// rather than restating it, so moving the format version does not mean
/// editing every fixture — which is how a fixture ends up asserting a
/// version the code no longer speaks.
String get currentVersionString => DriveStateFormatVersion.current.toString();

typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

void main() {
  const driveId = '00000000-0000-0000-0000-00000000d21e';
  const driveStateId = '00000000-0000-0000-0000-000000005747';
  final createdAt = DateTime.fromMillisecondsSinceEpoch(1234567890000);
  final body = Uint8List.fromList(List.generate(64, (i) => i));
  final cipherIv = Uint8List.fromList(List.generate(12, (i) => 12 - i));

  PackageInfo.setMockInitialValues(
    version: '1.3.3.7',
    packageName: 'ArDrive-Web-Test',
    appName: 'ArDrive-Web-Test',
    buildNumber: '420',
    buildSignature: 'Test signature',
  );

  DriveStateEntity entity() => DriveStateEntity(
        id: driveStateId,
        driveId: driveId,
        blockEnd: 1814228,
        dataStart: 1102394,
        dataEnd: 1814012,
        entityCount: 41273,
        cipher: CipherTag.aes256,
        cipherIv: encodeBytesToBase64(cipherIv),
        data: body,
      )..createdAt = createdAt;

  /// The tags as a client reading them back off GraphQL would see them.
  Map<String, String> tagsOf(TransactionBase tx) => {
        for (final tag in tx.tags)
          decodeBase64ToString(tag.name): decodeBase64ToString(tag.value),
      };

  group('DriveStateEntity', () {
    group('addEntityTagsToTransaction', () {
      test('adds every tag the format specifies, and only those', () {
        final tx = Transaction();

        entity().addEntityTagsToTransaction(tx);

        expect(tagsOf(tx), {
          EntityTag.arFs: '0.15',
          EntityTag.entityType: EntityTypeTag.driveState,
          EntityTag.driveId: driveId,
          EntityTag.driveStateId: driveStateId,
          EntityTag.stateVersion: currentVersionString,
          EntityTag.contentType: ContentType.octetStream,
          EntityTag.blockStart: '0',
          EntityTag.blockEnd: '1814228',
          EntityTag.dataStart: '1102394',
          EntityTag.dataEnd: '1814012',
          EntityTag.entityCount: '41273',
          EntityTag.cipher: 'AES256-GCM',
          EntityTag.cipherIv: encodeBytesToBase64(cipherIv),
        });
      });

      test(
          'never says Content-Encoding, whatever the body was compressed '
          'with', () {
        // The payload really is gzipped, and the tag would really be a lie:
        // the transaction's data is the ciphertext, and gzip is two layers
        // inside it. It matters because a gateway echoes this tag onto the
        // HTTP response, so a browser would gunzip the ciphertext and fail -
        // permanently, because tags cannot be changed. See the entity's own
        // documentation.
        final tx = Transaction();

        entity().addEntityTagsToTransaction(tx);

        expect(tagsOf(tx).keys, isNot(contains(EntityTag.contentEncoding)));
        expect(tagsOf(tx)[EntityTag.contentType], ContentType.octetStream);
      });

      test('publishes a full copy: Block-Start is always 0', () {
        final tx = Transaction();

        entity().addEntityTagsToTransaction(tx);

        expect(tagsOf(tx)[EntityTag.blockStart], '0');
      });

      /// A missing tag is not a programming slip that a debug build will catch
      /// for you. `assert` is compiled out of release, so a release client
      /// would interpolate the null, publish `Block-End: null`, pay for it,
      /// and hand every reader — including itself, which parses these with
      /// `int.parse` — a transaction that can never be used. Tags are
      /// immutable, so before the transaction exists is the only place to
      /// stop it.
      ///
      /// `flutter test` runs with asserts enabled, so a test that only proved
      /// "it throws" would prove nothing about release. These assert on the
      /// message instead: an `AssertionError` carries no field names, and a
      /// stripped assert carries nothing at all.
      group('refuses to tag an incomplete entity, in release as in debug', () {
        void expectRefusal(DriveStateEntity incomplete, String tag) {
          expect(
            () => incomplete.addEntityTagsToTransaction(Transaction()),
            throwsA(
              isA<StateError>().having((e) => e.message, 'message',
                  allOf(contains(tag), contains('no reader can use'))),
            ),
          );
        }

        test('a null Block-End', () {
          expectRefusal(entity()..blockEnd = null, 'Block-End');
        });

        test('a null Entity-Count', () {
          expectRefusal(entity()..entityCount = null, 'Entity-Count');
        });

        /// `Cipher` and `Cipher-IV` are the one pair that may legitimately be
        /// absent - that is what a public drive's artifact looks like - but
        /// never one without the other. A `Cipher` with no `Cipher-IV` is
        /// ciphertext nothing can address, and a `Cipher-IV` with no `Cipher`
        /// reads as an unencrypted artifact to every consumer, which for a
        /// private drive is the refusal at the far end of the cross-check.
        test('a Cipher with no Cipher-IV', () {
          expectRefusal(entity()..cipherIv = null, 'Cipher without Cipher-IV');
        });

        test('a Cipher-IV with no Cipher', () {
          expectRefusal(entity()..cipher = null, 'Cipher-IV without Cipher');
        });

        test('names every missing tag at once, so one fix is enough', () {
          final incomplete = entity()
            ..id = null
            ..blockEnd = null
            ..entityCount = null;

          expect(
            () => incomplete.addEntityTagsToTransaction(Transaction()),
            throwsA(isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Drive-State-Id'),
                contains('Block-End'),
                contains('Entity-Count'),
              ),
            )),
          );
        });

        test('writes no tag at all when it refuses', () {
          // Half a tag set on a transaction that is then signed anyway would
          // be the same permanent mistake with a different shape.
          final tx = Transaction();

          expect(
            () => (entity()..blockEnd = null).addEntityTagsToTransaction(tx),
            throwsA(isA<StateError>()),
          );
          expect(tx.tags, isEmpty);
        });
      });
    });

    group('asTransaction', () {
      test('carries the sealed body, the entity tags and the app tags',
          () async {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        final tx = await entity().asTransaction();
        final tags = tagsOf(tx);

        expect(tx.data, equals(body));
        expect(tags[EntityTag.entityType], EntityTypeTag.driveState);
        expect(tags.keys, isNot(contains(EntityTag.contentEncoding)));
        expect(tags[EntityTag.appName], 'ArDrive-App');
        expect(tags[EntityTag.appVersion], '1.3.3.7');
        expect(
          tags[EntityTag.unixTime],
          '${createdAt.millisecondsSinceEpoch ~/ 1000}',
        );
      });

      test('refuses a key: the body is sealed by the codec, not here',
          () async {
        expect(
          () => entity().asTransaction(key: SecretKey(List.filled(32, 0))),
          throwsA(isA<UnsupportedError>()),
        );
      });
    });

    group('asDataItem', () {
      test('carries the same tags as a transaction', () async {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        final item = await entity().asDataItem(null);

        expect(item.data, equals(body));
        expect(tagsOf(item)[EntityTag.driveStateId], driveStateId);
        expect(tagsOf(item)[EntityTag.entityCount], '41273');
      });

      test('refuses a key', () async {
        expect(
          () => entity().asDataItem(SecretKey(List.filled(32, 0))),
          throwsA(isA<UnsupportedError>()),
        );
      });
    });

    group('a public drive\'s artifact', () {
      DriveStateEntity publicEntity() => DriveStateEntity(
            id: driveStateId,
            driveId: driveId,
            blockEnd: 1814228,
            dataStart: 1102394,
            dataEnd: 1814012,
            entityCount: 41273,
            data: body,
          );

      test('tags without a Cipher or a Cipher-IV, rather than refusing', () {
        final tx = Transaction();
        publicEntity().addEntityTagsToTransaction(tx);

        final tags = tagsOf(tx);
        expect(tags.containsKey(EntityTag.cipher), isFalse);
        expect(tags.containsKey(EntityTag.cipherIv), isFalse);
      });

      test('writes every other tag exactly as a private artifact does', () {
        final tx = Transaction();
        publicEntity().addEntityTagsToTransaction(tx);

        final tags = tagsOf(tx);
        expect(tags[EntityTag.entityType], EntityTypeTag.driveState);
        expect(tags[EntityTag.driveId], driveId);
        expect(tags[EntityTag.driveStateId], driveStateId);
        expect(tags[EntityTag.stateVersion], currentVersionString);
        expect(tags[EntityTag.contentType], ContentType.octetStream);
        expect(tags[EntityTag.blockStart], '0');
        expect(tags[EntityTag.blockEnd], '1814228');
        expect(tags[EntityTag.entityCount], '41273');
      });

      test('is built from an envelope with nothing to put in either tag', () {
        final entity = DriveStateEntity.fromEnvelope(
          envelope: DriveStateEnvelope.inTheClear(body: body),
          id: driveStateId,
          driveId: driveId,
          coverage: const DriveStateCoverage(blockStart: 0, blockEnd: 1814228),
          dataStart: 1102394,
          dataEnd: 1814012,
          entityCount: 41273,
        );

        expect(entity.data, equals(body));
        expect(entity.cipher, isNull);
        expect(entity.cipherIv, isNull);
      });
    });

    group('fromEnvelope', () {
      test('takes the body and both cipher tags from the envelope', () {
        final entity = DriveStateEntity.fromEnvelope(
          envelope:
              DriveStateEnvelope.encrypted(body: body, cipherIv: cipherIv),
          id: driveStateId,
          driveId: driveId,
          coverage: const DriveStateCoverage(blockStart: 0, blockEnd: 1814228),
          dataStart: 1102394,
          dataEnd: 1814012,
          entityCount: 41273,
        );

        expect(entity.data, equals(body));
        expect(entity.cipher, CipherTag.aes256);
        expect(entity.cipherIv, encodeBytesToBase64(cipherIv));
        expect(entity.blockStart, 0);
        expect(entity.stateVersion, DriveStateFormatVersion.current);
      });
    });

    group('fromTransaction', () {
      test('reads back everything the entity wrote', () async {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        final published = await entity().asTransaction();
        final onChain = DriveHistoryTransaction.fromJson({
          'id': 'FAKE TX ID',
          'owner': {'address': 'FAKE WALLET ADDRESS'},
          'tags': [
            for (final tag in published.tags)
              {
                'name': decodeBase64ToString(tag.name),
                'value': decodeBase64ToString(tag.value),
              },
          ],
        });

        final read = await DriveStateEntity.fromTransaction(onChain, body);

        expect(read.id, driveStateId);
        expect(read.driveId, driveId);
        expect(read.stateVersion, DriveStateFormatVersion.current);
        expect(read.blockStart, 0);
        expect(read.blockEnd, 1814228);
        expect(read.dataStart, 1102394);
        expect(read.dataEnd, 1814012);
        expect(read.entityCount, 41273);
        expect(read.cipher, CipherTag.aes256);
        expect(read.cipherIv, encodeBytesToBase64(cipherIv));
        expect(read.data, equals(body));
        expect(read.txId, 'FAKE TX ID');
        expect(read.ownerAddress, 'FAKE WALLET ADDRESS');
        expect(read.createdAt, createdAt);
      });

      test('refuses a State-Version tag that is not major.minor', () async {
        // Every other tag is present and well formed, and the `1.0` case below
        // proves it: the only thing that decides these is the version.
        DriveHistoryTransaction taggedVersion(String version) =>
            DriveHistoryTransaction.fromJson({
              'id': 'FAKE TX ID',
              'owner': {'address': 'FAKE WALLET ADDRESS'},
              'tags': [
                {'name': EntityTag.driveStateId, 'value': driveStateId},
                {'name': EntityTag.driveId, 'value': driveId},
                {'name': EntityTag.stateVersion, 'value': version},
                {'name': EntityTag.blockStart, 'value': '0'},
                {'name': EntityTag.blockEnd, 'value': '1814228'},
                {'name': EntityTag.entityCount, 'value': '41273'},
                {'name': EntityTag.cipher, 'value': CipherTag.aes256},
                {
                  'name': EntityTag.cipherIv,
                  'value': encodeBytesToBase64(cipherIv),
                },
                {
                  'name': EntityTag.unixTime,
                  'value': '${createdAt.millisecondsSinceEpoch ~/ 1000}',
                },
              ],
            });

        // The positive control. Without it a missing tag elsewhere would make
        // every case below pass for a reason that has nothing to do with the
        // version - which is exactly how this test failed to catch anything on
        // its first draft.
        final read = await DriveStateEntity.fromTransaction(
          taggedVersion(currentVersionString),
          body,
        );
        expect(read.stateVersion, DriveStateFormatVersion.current);

        // The bare integer this tag used to carry is in the list on purpose.
        // Nothing has been published on chain, so there is no `"1"` to be
        // compatible with - and reading one as 1.0 would be a compatibility
        // path with no producer at the other end of it.
        for (final malformed in ['1', '1.0.0', '', 'x.y', '1.-1', '01.0']) {
          await expectLater(
            DriveStateEntity.fromTransaction(taggedVersion(malformed), body),
            throwsA(isA<EntityTransactionParseException>()),
            reason: '"$malformed" is not a version this client ever wrote',
          );
        }
      });

      test('throws the expected error for a transaction missing its tags',
          () async {
        final incomplete = DriveHistoryTransaction.fromJson({
          'id': 'FAKE TX ID',
          'owner': {'address': 'FAKE WALLET ADDRESS'},
          'tags': [
            {'name': EntityTag.driveStateId, 'value': driveStateId},
          ],
        });

        expect(
          () => DriveStateEntity.fromTransaction(incomplete, null),
          throwsA(isA<EntityTransactionParseException>()),
        );
      });
    });
  });
}
