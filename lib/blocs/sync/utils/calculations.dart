part of 'package:ardrive/blocs/sync/sync_cubit.dart';

/// Divided by 2 because we have 2 phases
double _calculateProgressInGetPhasePercentage(
  SyncProgress syncProgress,
  double currentDriveProgress,
) {
  return (currentDriveProgress / syncProgress.drivesCount) * 0.9;
} // 90%

double _calculateProgressInFetchPhasePercentage(
  SyncProgress syncProgress,
  double currentDriveProgress,
) {
  return (currentDriveProgress / syncProgress.drivesCount) * 0.1;
} // 10%

double _calculatePercentageProgress(
  double currentPercentage,
  double newPercentage,
) {
  return newPercentage - currentPercentage;
}
