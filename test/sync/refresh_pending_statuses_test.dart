import 'dart:async';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_cancellation_token.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class _MockSyncRepository extends Mock implements SyncRepository {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockActivityCubit extends MockCubit<ActivityState>
    implements ActivityCubit {}

class _MockActivityTracker extends Mock implements ActivityTracker {}

class _FakeWallet extends Fake implements Wallet {}

class _FakeSecretKey extends Fake implements SecretKey {}

/// Asking "did my upload land?" without starting a sync.
///
/// The status pass a sync ends with is already wallet-wide, and reads its
/// pending transactions out of the local tables rather than out of the walk -
/// so nothing about it needs a sync around it. Until now there was no way to
/// reach it: a reader watching a pending file either waited up to twenty
/// minutes for the confirmation watch, or ran a whole sync to ask one question.
void main() {
  late MockProfileCubit profileCubit;
  late _MockActivityCubit activityCubit;
  late MockPromptToSnapshotBloc promptToSnapshotBloc;
  late MockTabVisibilitySingleton tabVisibility;
  late MockConfigService configService;
  late MockConfig config;
  late _MockActivityTracker activityTracker;
  late _MockSyncRepository syncRepository;
  late _MockUserPreferencesRepository preferences;

  setUpAll(() {
    registerFallbackValue(_FakeWallet());
    registerFallbackValue(_FakeSecretKey());
  });

  setUp(() {
    profileCubit = MockProfileCubit();
    activityCubit = _MockActivityCubit();
    promptToSnapshotBloc = MockPromptToSnapshotBloc();
    tabVisibility = MockTabVisibilitySingleton();
    configService = MockConfigService();
    config = MockConfig();
    activityTracker = _MockActivityTracker();
    syncRepository = _MockSyncRepository();
    preferences = _MockUserPreferencesRepository();

    when(() => profileCubit.state).thenReturn(ProfileLoggingOut());
    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => false);
    when(() => activityCubit.state).thenReturn(ActivityNotRunning());
    when(() => tabVisibility.isTabFocused()).thenReturn(true);
    when(() => tabVisibility.onTabGetsFocused(any()))
        .thenAnswer((_) => StreamController<void>().stream.listen((_) {}));
    when(() => configService.config).thenReturn(config);
    when(() => config.autoSync).thenReturn(false);
    when(() => config.autoSyncIntervalInSeconds).thenReturn(3600);
    when(() => syncRepository.updateUserDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          onDriveRead: any(named: 'onDriveRead'),
          onDriveUnlocked: any(named: 'onDriveUnlocked'),
        )).thenAnswer((_) async {});
    when(() => syncRepository.hasPendingTransactions())
        .thenAnswer((_) async => false);
    when(() => syncRepository.probeDrivesWithChanges())
        .thenAnswer((_) async => const <String>{});
    when(() => syncRepository.refreshTransactionStatuses(
          ownerAddress: any(named: 'ownerAddress'),
          cancellationToken: any(named: 'cancellationToken'),
        )).thenAnswer((_) async {});
    when(() => preferences.load()).thenAnswer(
      (_) async => const UserPreferences(
        currentTheme: ArDriveThemes.dark,
        lastSelectedDriveId: null,
        syncAllDrivesOnLogin: false,
      ),
    );
  });

  SyncCubit buildCubit() => SyncCubit(
        profileCubit: profileCubit,
        activityCubit: activityCubit,
        promptToSnapshotBloc: promptToSnapshotBloc,
        tabVisibility: tabVisibility,
        configService: configService,
        activityTracker: activityTracker,
        syncRepository: syncRepository,
        userPreferencesRepository: preferences,
      );

  test('asks the gateway, and walks no history to do it', () async {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    expect(await cubit.refreshPendingStatuses(), isTrue);

    verify(() => syncRepository.refreshTransactionStatuses(
          ownerAddress: any(named: 'ownerAddress'),
          cancellationToken: any(named: 'cancellationToken'),
        )).called(1);

    // The whole point: it cannot invent a drive state, only settle one already
    // recorded. A sync here would be the sledgehammer this exists to avoid.
    verifyNever(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          onlyDriveIds: any(named: 'onlyDriveIds'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        ));
  });

  test('a gateway that refuses leaves the file showing what it showed',
      () async {
    when(() => syncRepository.refreshTransactionStatuses(
          ownerAddress: any(named: 'ownerAddress'),
          cancellationToken: any(named: 'cancellationToken'),
        )).thenThrow(Exception('gateway said no'));

    final cubit = buildCubit();
    addTearDown(cubit.close);

    // Answered, not thrown: the menu item reads this to decide whether it may
    // claim the check happened.
    expect(await cubit.refreshPendingStatuses(), isFalse);
  });

  /// The standing one-at-a-time rule. That sync ends with this very pass, so a
  /// second one would ask the same question twice and race its own answer.
  test('declines while a sync is already running', () async {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    cubit.emit(SyncInProgress());

    expect(await cubit.refreshPendingStatuses(), isFalse);
    verifyNever(() => syncRepository.refreshTransactionStatuses(
          ownerAddress: any(named: 'ownerAddress'),
          cancellationToken: any(named: 'cancellationToken'),
        ));
  });

  /// The hazard `sync_shutdown_test.dart` describes, reached by a new door.
  ///
  /// `ArDriveAuth.logout()` empties every table *before* this cubit closes, and
  /// `SyncRepository` is an app-level singleton above the auth gate - so an
  /// in-flight refresh would otherwise spend the next few seconds writing the
  /// previous wallet's transaction statuses into a database that has just been
  /// cleared.
  test('a refresh still in flight is cancelled when the cubit closes',
      () async {
    late SyncCancellationToken given;
    final released = Completer<void>();

    when(() => syncRepository.refreshTransactionStatuses(
          ownerAddress: any(named: 'ownerAddress'),
          cancellationToken: any(named: 'cancellationToken'),
        )).thenAnswer((invocation) {
      given = invocation.namedArguments[#cancellationToken]
          as SyncCancellationToken;

      return released.future;
    });

    final cubit = buildCubit();

    final refreshing = cubit.refreshPendingStatuses();
    await Future<void>.delayed(Duration.zero);

    expect(given.isCancelled, isFalse, reason: 'nothing has happened yet');

    await cubit.close();

    expect(
      given.isCancelled,
      isTrue,
      reason: 'the write has to be told to stop before the tables are emptied',
    );

    released.complete();

    // And it reports nothing, because the wallet it was about is gone.
    expect(await refreshing, isFalse);
  });
}
