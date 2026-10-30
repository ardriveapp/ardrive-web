import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/profile/profile_presence_hint.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart' show Selectable;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class _MockSelectable<T> extends Mock implements Selectable<T> {}

class _MemoryStore implements KeyValueStore {
  final values = <String, Object>{};

  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  Future<bool> putBool(String key, bool value) async {
    values[key] = value;
    return true;
  }

  @override
  String? getString(String key) => values[key] as String?;
  @override
  Future<bool> putString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async => values.remove(key) != null;
  @override
  Set<String> getKeys() => values.keys.toSet();
}

/// How a start reaches the sign-in panel: what it draws before the database
/// answers, and the clean-up of a visitor's drives, which now runs after the
/// panel is up. On a real database.
void main() {
  late Database db;
  late MockArDriveAuth auth;
  late StreamController<User?> authUsers;
  ProfileCubit? cubit;

  Future<void> insertDrive(String id) =>
      db.into(db.drives).insert(DrivesCompanion.insert(
            id: id,
            rootFolderId: 'root-$id',
            ownerAddress: 'someone',
            name: id,
            privacy: DrivePrivacyTag.public,
          ));

  Future<void> saveProfile() =>
      db.into(db.profiles).insert(ProfilesCompanion.insert(
            id: 'wallet-address',
            username: 'user',
            encryptedWallet: Uint8List(0),
            keySalt: Uint8List(0),
            walletPublicKey: 'public-key',
            encryptedPublicKey: Uint8List(0),
            profileType: ProfileType.json.index,
          ));

  Future<List<String>> driveIds() async =>
      (await db.driveDao.allDrives().get()).map((d) => d.id).toList();

  /// A profile DAO that finds no account without asking the database, for a
  /// test that holds the database.
  ProfileDao noProfileAnywhere() {
    final dao = MockProfileDao();
    final none = _MockSelectable<Profile>();
    when(() => none.getSingleOrNull()).thenAnswer((_) async => null);
    when(() => dao.defaultProfile()).thenReturn(none);
    return dao;
  }

  ProfileCubit buildCubit({ProfilePresenceHint? hint, ProfileDao? dao}) {
    final turboUploadService = MockTurboUploadService();
    when(() => turboUploadService.useTurboUpload).thenReturn(true);
    return cubit = ProfileCubit(
      turboUploadService: turboUploadService,
      profileDao: dao ?? db.profileDao,
      db: db,
      tabVisibilitySingleton: TabVisibilitySingleton(),
      arDriveAuth: auth,
      presenceHint: hint,
    );
  }

  setUp(() {
    db = getTestDb();
    auth = MockArDriveAuth();
    authUsers = StreamController<User?>.broadcast();
    when(() => auth.onAuthStateChanged()).thenAnswer((_) => authUsers.stream);
  });

  tearDown(() async {
    await cubit?.close();
    cubit = null;
    await authUsers.close();
    // Behind any clean-up still running.
    await db.customSelect('SELECT 1').get();
    await db.close();
  });

  group('the visitor clean-up', () {
    test(
        'runs after the sign-in panel is offered, and keeps what a visitor '
        'opens from it', () async {
      await insertDrive('left-by-a-visitor');

      // Hold the database, so the clean-up cannot run until let go.
      final held = Completer<void>();
      final holding = db.transaction(() async {
        await db.customSelect('SELECT 1').get();
        await held.future;
      });
      await pumpEventQueue();

      buildCubit(dao: noProfileAnywhere());
      // Offered while the clean-up still waits: nothing sits between the
      // database's answer and the panel.
      expect(
        await cubit!.stream.first.timeout(const Duration(seconds: 5)),
        isA<ProfilePromptAdd>(),
      );

      // A tap later, a visitor opens a drive from the panel.
      await Future<void>.delayed(Duration.zero);
      final opened = insertDrive('opened-from-the-panel');

      held.complete();
      await holding;
      await opened;

      expect(await driveIds(), ['opened-from-the-panel']);
    });

    test('nothing is cleaned up when there is an account', () async {
      await saveProfile();
      await insertDrive('mine');

      buildCubit();
      await expectLater(cubit!.stream, emits(isA<ProfilePromptLogIn>()));
      await pumpEventQueue();

      expect(await driveIds(), ['mine']);
    });
  });

  group('what the panel draws before the database answers', () {
    test('the hint while checking, the answer once it is in', () async {
      final store = _MemoryStore()
        ..values[ProfilePresenceHint.storageKey] = true;

      buildCubit(hint: ProfilePresenceHint(store));
      expect(cubit!.state, isA<ProfileCheckingAvailability>());
      expect(cubit!.presence, ProfilePresence.present);

      await expectLater(cubit!.stream, emits(isA<ProfilePromptAdd>()));
      expect(cubit!.presence, ProfilePresence.absent);
    });

    test('records what it found, for the next start', () async {
      final store = _MemoryStore()..values['config'] = '{}';
      buildCubit(hint: ProfilePresenceHint(store));
      await expectLater(cubit!.stream, emits(isA<ProfilePromptAdd>()));
      await pumpEventQueue();
      expect(store.values[ProfilePresenceHint.storageKey], isFalse);
      await cubit!.close();

      await saveProfile();
      buildCubit(hint: ProfilePresenceHint(store));
      expect(cubit!.presence, ProfilePresence.absent,
          reason: 'what the last start found');
      await expectLater(cubit!.stream, emits(isA<ProfilePromptLogIn>()));
      await pumpEventQueue();
      expect(cubit!.presence, ProfilePresence.present);
      expect(store.values[ProfilePresenceHint.storageKey], isTrue);
    });

    test('logging out records that the account is gone', () async {
      await saveProfile();
      final store = _MemoryStore();
      buildCubit(hint: ProfilePresenceHint(store));
      await expectLater(cubit!.stream, emits(isA<ProfilePromptLogIn>()));

      await cubit!.logoutProfile();
      await pumpEventQueue();

      expect(store.values[ProfilePresenceHint.storageKey], isFalse);
    });

    test('with no hint, unknown until the database answers', () async {
      buildCubit();
      expect(cubit!.presence, ProfilePresence.unknown);
      await expectLater(cubit!.stream, emits(isA<ProfilePromptAdd>()));
      expect(cubit!.presence, ProfilePresence.absent);
    });
  });

  group('ProfilePresenceHint', () {
    test('reads what was recorded', () {
      final store = _MemoryStore()..values['config'] = '{}';
      expect(ProfilePresenceHint(store).atStart, ProfilePresence.unknown);

      store.values[ProfilePresenceHint.storageKey] = true;
      expect(ProfilePresenceHint(store).atStart, ProfilePresence.present);

      store.values[ProfilePresenceHint.storageKey] = false;
      expect(ProfilePresenceHint(store).atStart, ProfilePresence.absent);
    });

    test('a store with nothing in it is a browser that never ran the app', () {
      expect(
          ProfilePresenceHint(_MemoryStore()).atStart, ProfilePresence.absent);
    });

    test('keeps the value it read at the start', () async {
      final store = _MemoryStore()..values['config'] = '{}';
      final hint = ProfilePresenceHint(store);
      await hint.record(present: true);
      expect(hint.atStart, ProfilePresence.unknown);
      expect(ProfilePresenceHint(store).atStart, ProfilePresence.present);
    });

    test('a store that fails reads as unknown and records nothing', () async {
      final hint = ProfilePresenceHint(_FailingStore());
      expect(hint.atStart, ProfilePresence.unknown);
      await hint.record(present: true);
    });
  });
}

class _FailingStore extends _MemoryStore {
  @override
  bool? getBool(String key) => throw StateError('no storage');
  @override
  Future<bool> putBool(String key, bool value) => throw StateError('no');
}
