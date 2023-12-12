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

  static KeyValueStore? _maybeStore;
  // Should be per-drive?
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
    CountOfTxsSyncedWithGql.countForDrive(
      event.driveId,
      event.txsSyncedWithGqlCount,
    );
  }

  Future<void> _onDriveSelected(
    SelectedDrive event,
    Emitter<PromptToSnapshotState> emit,
  ) async {
    if (event.driveId == null) {
      if (state is PromptToSnapshotIdle) {
        emit(const PromptToSnapshotIdle(driveId: null));
      }
    }

    final wouldDriveBenefitFromSnapshot = event.driveId != null &&
        CountOfTxsSyncedWithGql.wouldDriveBenefitFromSnapshot(
          event.driveId!,
          _numberOfTxsBeforeSnapshot,
        );

    await _debouncer.run(() async {
      final shouldAskAgain = await _shouldAskToSnapshotAgain();
      if (shouldAskAgain &&
          wouldDriveBenefitFromSnapshot &&
          !isClosed &&
          state is PromptToSnapshotIdle) {
        logger.d('Prompting to snapshot for ${event.driveId}');
        emit(PromptToSnapshotPrompting(driveId: event.driveId!));
      }
    }).catchError((e) {
      // It was cancelled
    });
  }

  Future<void> _onDriveSnapshotting(
    DriveSnapshotting event,
    Emitter<PromptToSnapshotState> emit,
  ) async {
    emit(PromptToSnapshotPrompting(driveId: event.driveId));
  }

  Future<void> _onDriveSnapshotted(
    DriveSnapshotted event,
    Emitter<PromptToSnapshotState> emit,
  ) async {
    CountOfTxsSyncedWithGql.resetForDrive(event.driveId);
    emit(PromptToSnapshotIdle(driveId: event.driveId));
  }

  Future<void> _onDismissDontAskAgain(
    DismissDontAskAgain event,
    Emitter<PromptToSnapshotState> emit,
  ) async {
    await _dontAskToSnapshotAgain();
    emit(PromptToSnapshotIdle(driveId: event.driveId));
  }

  Future<void> _dontAskToSnapshotAgain() async {
    await (await _store).putBool(storeKey, true);
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
