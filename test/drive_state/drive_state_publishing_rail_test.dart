import 'dart:convert';
import 'dart:io';

import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/drive_state/data/arweave_drive_state_uploader.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/domain/drive_state_uploader.dart';
import 'package:ardrive/drive_state/presentation/drive_state_publish_offer.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rail itself, asserted in one place.
///
/// `docs/drive-state/DECISIONS.md` D8 is "built and tested, never executed by
/// the loop". The capability now exists behind a human click, and these are
/// the properties that keep the rail where it was:
///
/// 1. the flag is off in every flavour's shipped config;
/// 2. with the flag off, nothing that can reach a network is even
///    constructed;
/// 3. with the flag off, the menu offers nothing, whatever else is true;
/// 4. the uploader that ships when publishing is off refuses both transports.
///
/// The fifth property — that `prepare()` never reaches `publish()` — is
/// asserted on every preparation path in
/// `presentation/drive_state_creation_cubit_test.dart`, where each `prepare`
/// case ends in `verifyNever(() => uploader.publish(...))`.
void main() {
  /// The property the other tests in this file could not see.
  ///
  /// Every test below asserts something about a *function* — that
  /// `driveStatePublishOffer` hides the entry, that `driveStateUploaderFor`
  /// returns the unwired uploader. All of them passed while a second entry
  /// point sat in `drive_detail_page.dart` checking only ownership and
  /// privacy, opening the publish modal with the feature switched off. A unit
  /// test cannot see a call site it was never handed.
  ///
  /// So this one reads the source. The invariant is about the codebase rather
  /// than about any object in it: *the modal is opened from nowhere that has
  /// not consulted the gate.* `vendored_pdfjs_test.dart` establishes the
  /// precedent for asserting on files rather than behaviour when that is where
  /// the property actually lives.
  group('every way into the publish flow is gated', () {
    test('nothing opens the modal without consulting the gate', () {
      const entryPoint = 'promptToCreateDriveState(';
      const gate = 'driveStatePublishOffer';

      final offenders = <String>[];

      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();

        // The declaration itself, not a call site.
        if (source.contains('Future<void> $entryPoint')) continue;
        if (!source.contains(entryPoint)) continue;
        if (source.contains(gate)) continue;

        offenders.add(file.path);
      }

      expect(
        offenders,
        isEmpty,
        reason: 'these files open the drive state publish modal without '
            'reading `$gate`, so the feature flag does not gate them: '
            '${offenders.join(', ')}',
      );
    });

    test(
        'the gate is actually consulted somewhere, so the check is not '
        'vacuous', () {
      final callers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where(
              (f) => f.readAsStringSync().contains('promptToCreateDriveState('))
          .toList();

      // The declaration plus its call sites. If this ever drops to one, the
      // test above is passing because nothing opens the modal at all.
      expect(callers.length, greaterThanOrEqualTo(2));
    });
  });

  group('the flag ships off', () {
    test('AppConfig defaults publishing to off', () {
      expect(
        AppConfig(
          allowedDataItemSizeForTurbo: 0,
          stripePublishableKey: '',
        ).enableDriveStatePublishing,
        isFalse,
      );
    });

    test('a config JSON with no opinion is off, not on', () {
      final config = AppConfig.fromJson(const {
        'allowedDataItemSizeForTurbo': 0,
        'stripePublishableKey': '',
      });

      expect(config.enableDriveStatePublishing, isFalse);
    });

    // Without this, every "ships off" assertion below would pass just as
    // happily against a key the deserialiser silently ignores.
    test('the key is actually read, so "off" means something', () {
      final config = AppConfig.fromJson(const {
        'allowedDataItemSizeForTurbo': 0,
        'stripePublishableKey': '',
        'enableDriveStatePublishing': true,
      });

      expect(config.enableDriveStatePublishing, isTrue);
    });

    // Read off disk rather than asserted from memory: the shipped default is
    // whatever these files say, and a flavour switched on by accident is the
    // failure this whole rail exists to prevent.
    for (final flavour in ['dev', 'staging', 'prod']) {
      test('$flavour.json ships with publishing off', () {
        final config = AppConfig.fromJson(
          json.decode(File('assets/config/$flavour.json').readAsStringSync())
              as Map<String, dynamic>,
        );

        expect(config.enableDriveStatePublishing, isFalse);
      });
    }
  });

  group('with publishing off, nothing that can publish is built', () {
    test('the network-capable uploader is never constructed', () {
      var built = false;

      final uploader = driveStateUploaderFor(
        publishingEnabled: false,
        whenEnabled: () {
          built = true;
          return _UnreachableUploader();
        },
      );

      expect(built, isFalse);
      expect(uploader, isA<UnwiredDriveStateUploader>());
    });

    test('turning it on is what builds the real one', () {
      final real = _UnreachableUploader();

      expect(
        driveStateUploaderFor(
          publishingEnabled: true,
          whenEnabled: () => real,
        ),
        same(real),
      );
    });

    test('the menu offers nothing, whatever else is true', () {
      expect(
        driveStatePublishOffer(
          publishingEnabled: false,
          isPrivateDrive: true,
          isDriveOwner: true,
          hasWritePermissions: true,
          driveIsEmpty: false,
        ),
        DriveStatePublishOffer.hidden,
      );
    });
  });

  group('the uploader that ships when publishing is off', () {
    for (final method in UploadMethod.values) {
      test('refuses ${method.name}, and says nothing was spent', () async {
        final result = await const UnwiredDriveStateUploader().publish(
          _artifact(),
          method: method,
        );

        expect(result.isPublished, isFalse);
        expect(result.txId, isNull);
        expect(result.reason, contains('Nothing was uploaded'));
        expect(result.reason, contains('nothing was spent'));
      });
    }
  });
}

PreparedDriveStateArtifact _artifact() => PreparedDriveStateArtifact(
      entity: DriveStateEntity(),
      driveId: 'drive-id',
      driveName: 'drive',
      entityCount: 1,
      sizeInBytes: 1,
    );

/// Stands in for the real uploader without being able to do anything: if the
/// rail ever lets it through in a test, the test fails rather than the network
/// being touched.
class _UnreachableUploader implements DriveStateUploader {
  @override
  Future<DriveStateUploadResult> publish(
    PreparedDriveStateArtifact artifact, {
    required UploadMethod method,
  }) async =>
      throw StateError(
        'The publishing rail let an upload through with the feature off.',
      );
}
