import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_state.dart';
import 'package:ardrive/utils/debouncer.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const Duration defaultDurationBeforePrompting = Duration(seconds: 20);
const int defaultNumberOfTxsBeforeSnapshot = 1000;

class PromptToSnapshotBloc
    extends Bloc<PromptToSnapshotEvent, PromptToSnapshotState> {
  late Duration _durationBeforePrompting;
  late Debouncer _debouncer;
  late int _numberOfTxsBeforeSnapshot;

  bool _isSyncRunning = false;

  static KeyValueStore? _maybeStore;
  static const storeKey = 'dont-ask-to-snapshot-again';

  Duration get durationBeforePrompting => _durationBeforePrompting;

  PromptToSnapshotBloc({
    KeyValueStore? store,
    Duration durationBeforePrompting = defaultDurationBeforePrompting,
    int numberOfTxsBeforeSnapshot = defaultNumberOfTxsBeforeSnapshot,
  }) : super(const PromptToSnapshotIdle(driveId: null)) {
    on<CountSyncedTxs>(_onCountSyncedTxs);
    on<SelectedDrive>(_onDriveSelected);
    on<DriveSnapshotting>(_onDriveSnapshotting);
    on<SyncRunning>(_onSyncRunning);
    on<DriveSnapshotted>(_onDriveSnapshotted);
    on<DismissDontAskAgain>(_onDismissDontAskAgain);

    _maybeStore ??= store;
    _durationBeforePrompting = durationBeforePrompting;
    _debouncer = Debouncer(delay: durationBeforePrompting);
    _numberOfTxsBeforeSnapshot = numberOfTxsBeforeSnapshot;
  }

  Future<KeyValueStore> get _store async {
    /// lazily initialize KeyValueStore
    _maybeStore ??= await LocalKeyValueStore.getInstance();
    return _maybeStore!;
  }

  Future<void> _onCountSyncedTxs(
    CountSyncedTxs event,
    Emitter<PromptToSnapshotState> emit,
  ) async {
    logger.d(
      '[PROMPT TO SNAPSHOT] Counting ${event.txsSyncedWithGqlCount} TXs for drive ${event.driveId}',
    );

    if (event.wasDeepSync) {
      logger.d('[PROMPT TO SNAPSHOT] The count came from a deep sync');
      CountOfTxsSyncedWithGql.resetForDrive(event.driveId);
    }

    CountOfTxsSyncedWithGql.countForDrive(
      event.driveId,
      event.txsSyncedWithGqlCount,
    );
  }

  Future<void> _onDriveSelected(
    SelectedDrive event,
    Emitter<PromptToSnapshotState> emit,
  ) async {
    if (_isSyncRunning) {
      return;
    }

    logger.d('[PROMPT TO SNAPSHOT] Selected drive ${event.driveId}');

    if (event.driveId == null) {
      if (state is PromptToSnapshotIdle) {
        logger.d(
            '[PROMPT TO SNAPSHOT] The drive id is null and the state is idle');
        emit(const PromptToSnapshotIdle(driveId: null));
      }
    }

    final shouldAskAgain = await _shouldAskToSnapshotAgain();
    final stateIsIdle = state is PromptToSnapshotIdle;

    logger.d(
      '[PROMPT TO SNAPSHOT] Will attempt to prompt for drive ${event.driveId}'
      ' in ${_durationBeforePrompting.inSeconds}s',
    );

    await _debouncer.run(() async {
      final wouldDriveBenefitFromSnapshot = event.driveId != null &&
          CountOfTxsSyncedWithGql.wouldDriveBenefitFromSnapshot(
            event.driveId!,
            _numberOfTxsBeforeSnapshot,
          );
      if (!_isSyncRunning &&
          shouldAskAgain &&
          wouldDriveBenefitFromSnapshot &&
          !isClosed &&
          stateIsIdle) {
        logger.d(
            '[PROMPT TO SNAPSHOT] Prompting to snapshot for ${event.driveId}');
        emit(PromptToSnapshotPrompting(driveId: event.driveId!));
      } else {
        logger.d(
          '[PROMPT TO SNAPSHOT] Didn\'t prompt for ${event.driveId}.'
          ' isSyncRunning: $_isSyncRunning'
          ' shoudAskAgain: $shouldAskAgain'
          ' wouldDriveBenefitFromSnapshot: $wouldDriveBenefitFromSnapshot'
          ' isBlocClosed: $isClosed'
          ' stateIsIdle: $stateIsIdle',
        );
      }
    }).catchError((e) {
      // It was cancelled
    });
  }

  void _onDriveSnapshotting(
    DriveSnapshotting event,
    Emitter<PromptToSnapshotState> emit,
  ) {
    logger.d('[PROMPT TO SNAPSHOT] Drive ${event.driveId} is snapshotting}');

    emit(PromptToSnapshotPrompting(driveId: event.driveId));
  }

  void _onSyncRunning(
    SyncRunning event,
    Emitter<PromptToSnapshotState> emit,
  ) {
    logger.d('[PROMPT TO SNAPSHOT] Sync status changed: ${event.isRunning}');

    _isSyncRunning = event.isRunning;
  }

  Future<void> _onDriveSnapshotted(
    DriveSnapshotted event,
    Emitter<PromptToSnapshotState> emit,
  ) async {
    logger.d(
      '[PROMPT TO SNAPSHOT] Drive ${event.driveId} was snapshotted'
      ' with ${event.txsSyncedWithGqlCount} TXs',
    );

    CountOfTxsSyncedWithGql.resetForDrive(event.driveId);
    CountOfTxsSyncedWithGql.countForDrive(
      event.driveId,
      event.txsSyncedWithGqlCount,
    );
    emit(PromptToSnapshotIdle(driveId: event.driveId));
  }

  Future<void> _onDismissDontAskAgain(
    DismissDontAskAgain event,
    Emitter<PromptToSnapshotState> emit,
  ) async {
    logger.d(
        '[PROMPT TO SNAPSHOT] Asked not to prompt again: ${event.dontAskAgain}');

    await _dontAskToSnapshotAgain(event.dontAskAgain);
    emit(PromptToSnapshotIdle(driveId: event.driveId));
  }

  Future<void> _dontAskToSnapshotAgain(
    bool dontAskAgain,
  ) async {
    await (await _store).putBool(storeKey, dontAskAgain);
  }

  Future<bool> _shouldAskToSnapshotAgain() async {
    final store = await _store;
    final value = await store.getBool(storeKey);
    return value != true;
  }
}

abstract class CountOfTxsSyncedWithGql {
  static final List<CountOfTxsSyncedWithGqlOfDrive>
      _countOfTxsSynceWithGqlOfDrive = [];

  static int _getForDrive(DriveID driveId) {
    return _countOfTxsSynceWithGqlOfDrive
            .firstWhereOrNull((e) => e.driveId == driveId)
            ?.count ??
        0;
  }

  static void countForDrive(DriveID driveId, int count) {
    final currentCount = _getForDrive(driveId);
    _countOfTxsSynceWithGqlOfDrive.removeWhere((e) => e.driveId == driveId);
    _countOfTxsSynceWithGqlOfDrive.add(CountOfTxsSyncedWithGqlOfDrive(
      count: currentCount + count,
      driveId: driveId,
    ));
  }

  static void resetForDrive(DriveID driveId) {
    _countOfTxsSynceWithGqlOfDrive.removeWhere((e) => e.driveId == driveId);
  }

  static bool wouldDriveBenefitFromSnapshot(
    DriveID driveId,
    int numberOfTxsBeforeSnapshot,
  ) {
    final count = _getForDrive(driveId);
    final wouldBenefit = count >= numberOfTxsBeforeSnapshot;

    logger.d(
      '[PROMPT TO SNAPSHOT] Would drive $driveId'
      ' ($count / $numberOfTxsBeforeSnapshot TXs) benefit from a snapshot:'
      ' $wouldBenefit',
    );

    return wouldBenefit;
  }
}

class CountOfTxsSyncedWithGqlOfDrive {
  final int count;
  final DriveID driveId;

  const CountOfTxsSyncedWithGqlOfDrive({
    required this.count,
    required this.driveId,
  });
}
