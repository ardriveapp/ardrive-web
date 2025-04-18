import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_state.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_utils/utils.dart';

const durationBeforePrompting = Duration(milliseconds: 200);
const numberOfTxsBeforeSnapshot = 3;
const driveId = 'test-drive-id';

void main() {
  late PromptToSnapshotBloc promptToSnapshotBloc;
  late KeyValueStore store;
  late UserRepository userRepository;
  late ProfileCubit profileCubit;
  late Database db;
  late DriveDao driveDao;
  late Wallet testWallet;
  late String walletAddress;
  late DriveID driveId;

  WidgetsFlutterBinding.ensureInitialized();

  group('PromptToSnapshotBloc class', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final fakePrefs = await SharedPreferences.getInstance();
      store = await LocalKeyValueStore.getInstance(prefs: fakePrefs);

      userRepository = MockUserRepository();
      when(() => userRepository.getOwnerOfDefaultProfile())
          .thenAnswer((_) => Future.value('test-owner'));

      testWallet = getTestWallet();
      walletAddress = await testWallet.getAddress();

      profileCubit = MockProfileCubit();
      when(() => profileCubit.state).thenReturn(ProfileLoggedIn(
        user: User(
          password: 'test-password',
          wallet: testWallet,
          walletAddress: walletAddress,
          walletBalance: BigInt.one,
          cipherKey: SecretKey(List.generate(32, (index) => index)),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        ),
        useTurbo: false,
      ));

      db = getTestDb();
      driveDao = db.driveDao;

      final drive = await driveDao.createDrive(
        name: "Mati's drive",
        ownerAddress: walletAddress,
        privacy: 'public',
        wallet: testWallet,
        password: '123',
        profileKey: SecretKey([1, 2, 3, 4, 5]),
        signatureType: '1',
      );
      driveId = drive.driveId;
    });

    setUp(() {
      promptToSnapshotBloc = PromptToSnapshotBloc(
        store: store,
        durationBeforePrompting: durationBeforePrompting,
        numberOfTxsBeforeSnapshot: numberOfTxsBeforeSnapshot,
        userRepository: userRepository,
        profileCubit: profileCubit,
        driveDao: driveDao,
      );
    });

    blocTest(
      'can count through txs',
      build: () => promptToSnapshotBloc,
      act: (PromptToSnapshotBloc bloc) async {
        bloc.add(CountSyncedTxs(
          driveId: driveId,
          txsSyncedWithGqlCount: 1,
          wasDeepSync: false,
        ));
        bloc.add(CountSyncedTxs(
          driveId: driveId,
          txsSyncedWithGqlCount: 2,
          wasDeepSync: false,
        ));
        bloc.add(CountSyncedTxs(
          driveId: driveId,
          txsSyncedWithGqlCount: 3,
          wasDeepSync: false,
        ));
      },
      expect: () => [
        // By this point we've counted 6 TXs
      ],
    );

    blocTest(
      'will prompt to snapshot after enough txs',
      build: () => promptToSnapshotBloc,
      act: (PromptToSnapshotBloc bloc) async {
        bloc.add(SelectedDrive(driveId: driveId));
        const durationAfterPrompting = Duration(milliseconds: 250);
        await Future<void>.delayed(durationAfterPrompting);
      },
      expect: () => [
        PromptToSnapshotPrompting(driveId: driveId),
      ],
    );

    blocTest(
      'will not prompt to snapshot if drive is deselected',
      build: () => promptToSnapshotBloc,
      act: (PromptToSnapshotBloc bloc) async {
        bloc.add(SelectedDrive(driveId: driveId));

        // This delay sumulates the user moving the cursor to a different drive.
        /// Without this delay, the test will fail because the bloc will
        /// first handle the event for nulling the driveId, and then handle
        /// the event for selecting the driveId.
        await Future<void>.delayed(const Duration(milliseconds: 1));

        bloc.add(const SelectedDrive(driveId: null));
        const durationAfterPrompting = Duration(milliseconds: 250);
        await Future<void>.delayed(durationAfterPrompting);
      },
      expect: () => [
        const PromptToSnapshotIdle(),
      ],
    );

    blocTest(
      'selecting an already snapshotted drive does nothing',
      build: () => promptToSnapshotBloc,
      act: (PromptToSnapshotBloc bloc) async {
        bloc.add(DriveSnapshotted(driveId: driveId));
        bloc.add(SelectedDrive(driveId: driveId));
        const durationAfterPrompting = Duration(milliseconds: 250);
        await Future<void>.delayed(durationAfterPrompting);
      },
      expect: () => [
        const PromptToSnapshotIdle(),
      ],
    );

    blocTest(
      'selecting a drive after choosing not to be asked again does nothing',
      build: () => promptToSnapshotBloc,
      act: (PromptToSnapshotBloc bloc) async {
        bloc.add(const DismissDontAskAgain(dontAskAgain: false));
        bloc.add(SelectedDrive(driveId: driveId));
        const durationAfterPrompting = Duration(milliseconds: 250);
        await Future<void>.delayed(durationAfterPrompting);
      },
      expect: () => [
        const PromptToSnapshotIdle(),
      ],
    );

    blocTest(
      'selecting a drive after choosing to be asked again does prompt',
      build: () => promptToSnapshotBloc,
      act: (PromptToSnapshotBloc bloc) async {
        bloc.add(const DismissDontAskAgain(dontAskAgain: true));
        bloc.add(SelectedDrive(driveId: driveId));
        const durationAfterPrompting = Duration(milliseconds: 250);
        await Future<void>.delayed(durationAfterPrompting);
      },
      expect: () => [
        const PromptToSnapshotIdle(),
      ],
    );

    blocTest(
      'selecting a drive while not logged in does nothing',
      build: () => promptToSnapshotBloc,
      act: (PromptToSnapshotBloc bloc) async {
        when(() => userRepository.getOwnerOfDefaultProfile())
            .thenAnswer((_) => Future.value(null));
        bloc.add(SelectedDrive(driveId: driveId));
        const durationAfterPrompting = Duration(milliseconds: 250);
        await Future<void>.delayed(durationAfterPrompting);
      },
      expect: () => [],
    );

    blocTest(
      'selecting a drive while sync is running does nothing',
      build: () => promptToSnapshotBloc,
      act: (PromptToSnapshotBloc bloc) async {
        bloc.add(SelectedDrive(driveId: driveId));
        const durationAfterPrompting = Duration(milliseconds: 250);
        await Future<void>.delayed(durationAfterPrompting);
      },
      expect: () => [],
    );

    blocTest(
      'won\'t prompt to snapshot if drive is already snapshotting',
      build: () => promptToSnapshotBloc,
      act: (PromptToSnapshotBloc bloc) async {
        bloc.add(SelectedDrive(driveId: driveId));
        await Future<void>.delayed(const Duration(milliseconds: 1));
        bloc.add(DriveSnapshotting(driveId: driveId));
        const durationAfterPrompting = Duration(milliseconds: 250);
        await Future<void>.delayed(durationAfterPrompting);
      },
      expect: () => [
        PromptToSnapshotSnapshotting(driveId: driveId),
      ],
    );

    blocTest(
      'selecting a drive whith no write permissions does nothing',
      build: () => promptToSnapshotBloc,
      act: (PromptToSnapshotBloc bloc) async {
        when(() => profileCubit.state).thenReturn(ProfileLoggedIn(
          user: User(
            password: 'test-password',
            wallet: testWallet,
            walletAddress: walletAddress,
            walletBalance: BigInt.one,
            cipherKey: SecretKey(List.generate(32, (index) => index)),
            profileType: ProfileType.json,
            errorFetchingIOTokens: false,
          ),
          useTurbo: false,
        ));
        bloc.add(SelectedDrive(driveId: driveId));
        const durationAfterPrompting = Duration(milliseconds: 250);
        await Future<void>.delayed(durationAfterPrompting);
      },
      expect: () => [],
    );
  });
}
