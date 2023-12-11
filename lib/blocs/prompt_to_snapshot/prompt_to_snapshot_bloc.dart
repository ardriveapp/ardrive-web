import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_state.dart';
import 'package:ardrive/utils/debouncer.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const int secondsBeforePrompting = 20;
const int numberOfTxsBeforeSnapshot = 1000;

class PromptToSnapshotBloc
    extends Bloc<PromptToSnapshotEvent, PromptToSnapshotState> {
  final Debouncer _debouncer = Debouncer(
    delay: const Duration(seconds: secondsBeforePrompting),
  );

  PromptToSnapshotBloc() : super(const PromptToSnapshotIdle(driveId: null)) {
    on<CountSyncedTxs>(_onCountSyncedTxs);
    on<SelectedDrive>(_onSelectedDrive);
    on<DriveSnapshotting>(_onDriveSnapshotting);
    on<DriveSnapshotted>(_onDriveSnapshotted);
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

  Future<void> _onSelectedDrive(
    SelectedDrive event,
    Emitter<PromptToSnapshotState> emit,
  ) async {
    logger.d('Selected drive: ${event.driveId}');

    if (event.driveId == null) {
      if (state is PromptToSnapshotIdle) {
        emit(const PromptToSnapshotIdle(driveId: null));
      }
      return;
    }

    final shouldPrompt =
        CountOfTxsSyncedWithGql.wouldDriveBenefitFromSnapshot(event.driveId!);

    logger.d(
      'Debouncing prompt to snapshot (${event.driveId}): '
      'should prompt: $shouldPrompt, is closed: $isClosed',
    );

    await _debouncer.run(() {
      logger.d('Debouncer finished for ${event.driveId}');
      if (shouldPrompt && !isClosed && state is PromptToSnapshotIdle) {
        logger.d('Prompting to snapshot for ${event.driveId}');
        emit(PromptToSnapshotPrompting(driveId: event.driveId!));
      }
    }).catchError((e) {
      logger.d('Debouncer cancelled: $e');
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
    logger.d(
      'Count of txs synced with gql for $driveId: $count,'
      ' total: ${currentCount + count}}',
    );
  }

  static void resetForDrive(DriveID driveId) {
    _countOfTxsSynceWithGqlOfDrive.removeWhere((e) => e.driveId == driveId);
    logger.d('Reset count of txs synced with gql for $driveId');
  }

  static bool wouldDriveBenefitFromSnapshot(DriveID driveId) {
    // TODO: remove this
    return true;

    final count = _getForDrive(driveId);
    final wouldBenefit = count >= numberOfTxsBeforeSnapshot;
    logger.d(
      'Would drive $driveId benefit from snapshot? $wouldBenefit,'
      ' count: $count',
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
