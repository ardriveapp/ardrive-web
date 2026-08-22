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
/// 1. both feature flags are off in every flavour's shipped config, are named
///    there rather than merely absent, and can each be switched on;
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

    /// The same kind of invariant, for the condition that was *removed*.
    ///
    /// Privacy is no longer one of the gate's inputs, and a unit test cannot
    /// see the way that comes back: an optional `isPrivateDrive` parameter
    /// defaulting to `true` compiles, passes every row of the matrix, and
    /// changes nothing — until one call site starts passing the drive's actual
    /// privacy, at which point public drives silently lose the menu entry
    /// again with no test anywhere disagreeing.
    ///
    /// So the property is asserted where it lives: no caller of the gate names
    /// privacy at all.
    test('no call site passes a privacy argument to the gate', () {
      const gate = 'driveStatePublishOffer';
      final offenders = <String>[];

      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        if (!source.contains(gate)) continue;
        if (!source.contains('isPrivateDrive')) continue;

        offenders.add(file.path);
      }

      expect(
        offenders,
        isEmpty,
        reason: 'a public drive publishes the same artifact with the '
            'encryption step absent, so `$gate` takes no privacy argument; '
            'these files pass one: ${offenders.join(', ')}',
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

  /// Both flags, not one.
  ///
  /// `AppConfig` documents these as "two risks, two switches" — reading an
  /// artifact costs nothing and every failure behind it is a fallback;
  /// publishing one spends real money and cannot be undone. That only holds
  /// while both switches exist. `enableSyncFromDriveState` had no key in any
  /// shipped config and no control anywhere, so the half of the feature that
  /// spends money was the reachable half: a user could publish artifacts that
  /// no build could read.
  ///
  /// So the assertions below are parameterised over both. The *presence* of
  /// the key is asserted as its own property, because a flag defaulting to
  /// false with nothing naming it reads identically to a flag that ships off
  /// deliberately, and only one of those can be switched on.
  group('the flags ship off', () {
    const flags = <String, bool Function(AppConfig)>{
      'enableSyncFromDriveState': _syncFromDriveState,
      'enableDriveStatePublishing': _publishing,
    };

    AppConfig configFor(Map<String, dynamic> extra) => AppConfig.fromJson({
          'allowedDataItemSizeForTurbo': 0,
          'stripePublishableKey': '',
          ...extra,
        });

    Map<String, dynamic> flavourJson(String flavour) =>
        json.decode(File('assets/config/$flavour.json').readAsStringSync())
            as Map<String, dynamic>;

    for (final entry in flags.entries) {
      final name = entry.key;
      final read = entry.value;

      test('AppConfig defaults $name to off', () {
        expect(
          read(AppConfig(
            allowedDataItemSizeForTurbo: 0,
            stripePublishableKey: '',
          )),
          isFalse,
        );
      });

      test('a config JSON with no opinion on $name is off, not on', () {
        expect(read(configFor(const {})), isFalse);
      });

      // Without this, every "ships off" assertion would pass just as happily
      // against a key the deserialiser silently ignores.
      test('$name is actually read, so "off" means something', () {
        expect(read(configFor({name: true})), isTrue);
      });

      // Read off disk rather than asserted from memory: the shipped default is
      // whatever these files say, and a flavour switched on by accident is the
      // failure this whole rail exists to prevent.
      for (final flavour in ['dev', 'staging', 'prod']) {
        test('$flavour.json ships with $name off', () {
          expect(read(AppConfig.fromJson(flavourJson(flavour))), isFalse);
        });

        // A key that is absent is not a key that is off. It deserialises the
        // same way, and that is the point: the flavour files are where a
        // release decides what ships, and a flag they do not mention is one
        // nobody reviewing them knows exists.
        test('$flavour.json says so explicitly, rather than by omission', () {
          expect(flavourJson(flavour), containsPair(name, false));
        });
      }

      // The switch a person actually reaches for. `ConfigFetcher` only
      // replaces a stored config when the asset's `configVersion` grows, and
      // bumping that wipes every other stored preference — so for anyone who
      // has already run the app, editing the JSON does nothing. Dev tools is
      // the only way to turn either of these on.
      test('$name can be switched on from dev tools', () {
        final source =
            File('lib/dev_tools/app_dev_tools.dart').readAsStringSync();

        expect(
          source,
          contains("name: '$name'"),
          reason: 'a flag with no config key that reaches a user and no '
              'dev-tools control is a flag nobody can turn on',
        );
        expect(source, contains('copyWith($name: value)'));
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

// Torn off rather than written as closures in the map literal so the map can
// be `const`, and so a renamed field is a compile error here rather than a
// silently unasserted flag.
bool _syncFromDriveState(AppConfig c) => c.enableSyncFromDriveState;

bool _publishing(AppConfig c) => c.enableDriveStatePublishing;

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
