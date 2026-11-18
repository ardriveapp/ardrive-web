import 'dart:math';
import 'package:ardrive/utils/logger.dart';

/// Simulator for testing sync failure scenarios
/// Only active in debug mode or when explicitly enabled
class SyncFailureSimulator {
  static SyncFailureSimulator? _instance;
  
  static SyncFailureSimulator get instance {
    _instance ??= SyncFailureSimulator._();
    return _instance!;
  }
  
  SyncFailureSimulator._();
  
  bool _enabled = false;
  FailureMode _mode = FailureMode.none;
  double _failureRate = 0.5; // 50% failure rate by default
  final Random _random = Random();
  
  // Configuration
  bool get isEnabled => _enabled;
  FailureMode get mode => _mode;
  
  void enable(FailureMode mode, {double failureRate = 0.5}) {
    _enabled = true;
    _mode = mode;
    _failureRate = failureRate.clamp(0.0, 1.0);
    logger.w('🧪 Sync Failure Simulator ENABLED - Mode: $mode, Rate: ${(_failureRate * 100).toInt()}%');
  }
  
  void disable() {
    _enabled = false;
    _mode = FailureMode.none;
    logger.i('🧪 Sync Failure Simulator DISABLED');
  }
  
  /// Check if we should simulate a failure for this drive
  bool shouldFailDrive(String driveId) {
    if (!_enabled || _mode == FailureMode.none) return false;
    
    switch (_mode) {
      case FailureMode.allFail:
        return true;
      case FailureMode.firstDriveFails:
        // Fail the first drive in the sync
        return _isFirstDrive(driveId);
      case FailureMode.randomFailures:
        // Random chance of failure based on rate
        return _random.nextDouble() < _failureRate;
      case FailureMode.alternatingFailures:
        // Fail every other drive
        return driveId.hashCode % 2 == 0;
      case FailureMode.none:
        return false;
    }
  }
  
  /// Get the simulated error for testing
  Exception getSimulatedError(String driveId) {
    final errorType = _random.nextInt(5);
    
    switch (errorType) {
      case 0:
        return Exception('504 Gateway Timeout - The server did not respond in time');
      case 1:
        return Exception('502 Bad Gateway - Invalid response from upstream server');
      case 2:
        return Exception('503 Service Unavailable - Server is temporarily unavailable');
      case 3:
        return Exception('GraphQL Error: Network timeout after 30 seconds');
      case 4:
        return Exception('Network error: Failed to connect to gateway');
      default:
        return Exception('Unknown error occurred during sync');
    }
  }
  
  bool _isFirstDrive(String driveId) {
    // Simple heuristic - you might want to track this more explicitly
    _firstDriveId ??= driveId;
    return _firstDriveId == driveId;
  }
  
  String? _firstDriveId;
  
  void resetFirstDrive() {
    _firstDriveId = null;
  }
}

enum FailureMode {
  none,
  allFail,           // All drives fail
  firstDriveFails,   // Only first drive fails
  randomFailures,    // Random drives fail based on rate
  alternatingFailures, // Every other drive fails
}

/// Extension to make it easy to use in the sync repository
extension SyncFailureSimulatorX on SyncFailureSimulator {
  /// Inject a failure if conditions are met
  Future<void> maybeInjectFailure(String driveId) async {
    if (shouldFailDrive(driveId)) {
      logger.w('🧪 SIMULATING FAILURE for drive: $driveId');
      
      // Add a small delay to simulate network timeout
      await Future.delayed(Duration(seconds: _random.nextInt(3) + 1));
      
      throw getSimulatedError(driveId);
    }
  }
}