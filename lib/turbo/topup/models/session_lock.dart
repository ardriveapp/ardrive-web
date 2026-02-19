import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Session lock for preventing concurrent top-up sessions across browser tabs.
///
/// Stored in localStorage with key 'ardrive_topup_session_lock'.
/// Auto-expires after 30 minutes (stale session protection).
class CryptoTopupSessionLock extends Equatable {
  /// Unique identifier for this tab
  final String tabId;

  /// When the lock was created
  final DateTime timestamp;

  /// Current state of the locked session
  final String state;

  /// Optional: the Arweave address for this session
  final String? arweaveAddress;

  const CryptoTopupSessionLock({
    required this.tabId,
    required this.timestamp,
    required this.state,
    this.arweaveAddress,
  });

  /// Check if this lock is stale (older than 30 minutes)
  bool get isStale =>
      DateTime.now().difference(timestamp) > const Duration(minutes: 30);

  /// Check if this lock is still valid (not stale)
  bool get isValid => !isStale;

  /// Check if this lock belongs to a different tab
  bool isDifferentTab(String currentTabId) => tabId != currentTabId;

  /// Create a new lock for the current session
  factory CryptoTopupSessionLock.create({
    required String tabId,
    required String state,
    String? arweaveAddress,
  }) {
    return CryptoTopupSessionLock(
      tabId: tabId,
      timestamp: DateTime.now(),
      state: state,
      arweaveAddress: arweaveAddress,
    );
  }

  /// Parse from JSON string (localStorage format)
  factory CryptoTopupSessionLock.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return CryptoTopupSessionLock(
      tabId: json['tabId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      state: json['state'] as String,
      arweaveAddress: json['arweaveAddress'] as String?,
    );
  }

  /// Convert to JSON string for localStorage
  String toJsonString() {
    return jsonEncode({
      'tabId': tabId,
      'timestamp': timestamp.toIso8601String(),
      'state': state,
      if (arweaveAddress != null) 'arweaveAddress': arweaveAddress,
    });
  }

  /// Update the state of this lock
  CryptoTopupSessionLock withState(String newState) {
    return CryptoTopupSessionLock(
      tabId: tabId,
      timestamp: DateTime.now(), // Refresh timestamp on state change
      state: newState,
      arweaveAddress: arweaveAddress,
    );
  }

  @override
  List<Object?> get props => [tabId, timestamp, state, arweaveAddress];

  @override
  String toString() {
    return 'CryptoTopupSessionLock{tabId: $tabId, state: $state, '
        'timestamp: $timestamp, isStale: $isStale}';
  }
}

/// Session lock states that indicate what phase the locked session is in
class SessionLockState {
  static const String tokenSelection = 'token_selection';
  static const String walletConnection = 'wallet_connection';
  static const String amountEntry = 'amount_entry';
  static const String confirmation = 'confirmation';
  static const String processing = 'processing';

  /// States that should block a new session from starting
  static const List<String> blockingStates = [
    amountEntry,
    confirmation,
    processing,
  ];

  /// Check if a state is blocking
  static bool isBlocking(String state) => blockingStates.contains(state);
}
