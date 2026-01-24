import 'dart:convert';

import 'package:ardrive/turbo/topup/models/pending_transaction.dart';
import 'package:ardrive/turbo/topup/models/session_lock.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Storage service for pending cryptocurrency transactions and session locks.
///
/// Uses SharedPreferences (localStorage on web) to persist:
/// - Pending transactions for recovery
/// - Session locks for cross-tab coordination
///
/// This class is a singleton to ensure only one tab ID exists per page load.
/// Use [CryptoTransactionStorage.getInstance()] to get the singleton instance.
class CryptoTransactionStorage {
  static const _pendingTxKey = 'pending_crypto_transactions';
  static const _sessionLockKey = 'ardrive_topup_session_lock';

  /// Singleton instance
  static CryptoTransactionStorage? _instance;

  /// Tab ID is generated once per page load and stored in the singleton
  static final String _tabId = const Uuid().v4();

  final SharedPreferences _prefs;

  /// Private constructor for singleton pattern
  CryptoTransactionStorage._internal(this._prefs);

  /// Get the singleton instance of CryptoTransactionStorage.
  ///
  /// This ensures only one tab ID exists per page load, which is critical
  /// for session lock comparisons to work correctly.
  static Future<CryptoTransactionStorage> getInstance() async {
    if (_instance == null) {
      final prefs = await SharedPreferences.getInstance();
      _instance = CryptoTransactionStorage._internal(prefs);
    }
    return _instance!;
  }

  /// Get the singleton instance synchronously if SharedPreferences is already available.
  ///
  /// Use this when you already have a SharedPreferences instance.
  /// Prefer [getInstance()] when possible.
  factory CryptoTransactionStorage(SharedPreferences prefs) {
    _instance ??= CryptoTransactionStorage._internal(prefs);
    return _instance!;
  }

  /// Current tab's unique identifier (same for all instances in this page load)
  String get tabId => _tabId;

  // ============================================
  // Pending Transactions
  // ============================================

  /// Save a pending transaction for recovery
  Future<void> savePendingTransaction(PendingCryptoTransaction tx) async {
    try {
      final transactions = await getAllPendingTransactions();

      // Remove any existing transaction with the same ID
      transactions.removeWhere((t) => t.transactionId == tx.transactionId);

      // Add the new transaction
      transactions.add(tx);

      // Save back to storage
      final jsonList = transactions.map((t) => t.toJson()).toList();
      await _prefs.setString(_pendingTxKey, jsonEncode(jsonList));

      logger.d('Saved pending transaction: ${tx.transactionId}');
    } catch (e) {
      logger.e('Error saving pending transaction: $e');
      rethrow;
    }
  }

  /// Get a pending transaction for a specific Arweave address
  Future<PendingCryptoTransaction?> getPendingTransaction(
      String arweaveAddress) async {
    try {
      final transactions = await getAllPendingTransactions();

      // Find the most recent non-stale transaction for this address
      final matching = transactions
          .where((t) => t.arweaveAddress == arweaveAddress && !t.isStale)
          .toList();

      if (matching.isEmpty) return null;

      // Sort by creation date, newest first
      matching.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return matching.first;
    } catch (e) {
      logger.e('Error getting pending transaction: $e');
      return null;
    }
  }

  /// Remove a pending transaction by ID
  Future<void> removePendingTransaction(String transactionId) async {
    try {
      final transactions = await getAllPendingTransactions();
      transactions.removeWhere((t) => t.transactionId == transactionId);

      final jsonList = transactions.map((t) => t.toJson()).toList();
      await _prefs.setString(_pendingTxKey, jsonEncode(jsonList));

      logger.d('Removed pending transaction: $transactionId');
    } catch (e) {
      logger.e('Error removing pending transaction: $e');
      rethrow;
    }
  }

  /// Get all pending transactions
  Future<List<PendingCryptoTransaction>> getAllPendingTransactions() async {
    try {
      final jsonString = _prefs.getString(_pendingTxKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((json) =>
              PendingCryptoTransaction.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logger.e('Error getting all pending transactions: $e');
      return [];
    }
  }

  /// Clean up stale transactions (older than 24 hours)
  Future<int> cleanupStaleTransactions() async {
    try {
      final transactions = await getAllPendingTransactions();
      final originalCount = transactions.length;

      transactions.removeWhere((t) => t.isStale);

      if (transactions.length < originalCount) {
        final jsonList = transactions.map((t) => t.toJson()).toList();
        await _prefs.setString(_pendingTxKey, jsonEncode(jsonList));

        final removedCount = originalCount - transactions.length;
        logger.d('Cleaned up $removedCount stale transactions');
        return removedCount;
      }

      return 0;
    } catch (e) {
      logger.e('Error cleaning up stale transactions: $e');
      return 0;
    }
  }

  // ============================================
  // Session Locks (Cross-Tab Coordination)
  // ============================================

  /// Acquire a session lock for the current tab
  Future<bool> acquireSessionLock(String state, {String? arweaveAddress}) async {
    try {
      final existingLock = await getSessionLock();

      // Check if another tab has a valid lock
      if (existingLock != null &&
          existingLock.isValid &&
          existingLock.isDifferentTab(_tabId)) {
        logger.d('Session lock held by another tab: ${existingLock.tabId}');
        return false;
      }

      // Create new lock for this tab
      final lock = CryptoTopupSessionLock.create(
        tabId: _tabId,
        state: state,
        arweaveAddress: arweaveAddress,
      );

      await _prefs.setString(_sessionLockKey, lock.toJsonString());
      logger.d('Acquired session lock: $state');
      return true;
    } catch (e) {
      logger.e('Error acquiring session lock: $e');
      return false;
    }
  }

  /// Update the state of the current session lock
  Future<bool> updateSessionLockState(String newState) async {
    try {
      final existingLock = await getSessionLock();

      // Can only update if we own the lock
      if (existingLock == null || existingLock.tabId != _tabId) {
        logger.w('Cannot update session lock - not owned by this tab');
        return false;
      }

      final updatedLock = existingLock.withState(newState);
      await _prefs.setString(_sessionLockKey, updatedLock.toJsonString());
      logger.d('Updated session lock state: $newState');
      return true;
    } catch (e) {
      logger.e('Error updating session lock: $e');
      return false;
    }
  }

  /// Release the session lock for the current tab
  Future<void> releaseSessionLock() async {
    try {
      final existingLock = await getSessionLock();

      // Only release if we own the lock
      if (existingLock != null && existingLock.tabId == _tabId) {
        await _prefs.remove(_sessionLockKey);
        logger.d('Released session lock');
      }
    } catch (e) {
      logger.e('Error releasing session lock: $e');
    }
  }

  /// Force release any session lock (used when user clicks "Cancel Other Session")
  Future<void> forceReleaseSessionLock() async {
    try {
      await _prefs.remove(_sessionLockKey);
      logger.d('Force released session lock');
    } catch (e) {
      logger.e('Error force releasing session lock: $e');
    }
  }

  /// Get the current session lock (if any)
  Future<CryptoTopupSessionLock?> getSessionLock() async {
    try {
      final jsonString = _prefs.getString(_sessionLockKey);
      if (jsonString == null || jsonString.isEmpty) {
        return null;
      }

      final lock = CryptoTopupSessionLock.fromJsonString(jsonString);

      // Auto-clear stale locks
      if (lock.isStale) {
        await _prefs.remove(_sessionLockKey);
        logger.d('Auto-cleared stale session lock');
        return null;
      }

      return lock;
    } catch (e) {
      logger.e('Error getting session lock: $e');
      return null;
    }
  }

  /// Check if another tab has an active session
  Future<bool> hasActiveSessionInOtherTab() async {
    final lock = await getSessionLock();
    return lock != null && lock.isValid && lock.isDifferentTab(_tabId);
  }

  /// Check if the current tab owns the session lock
  Future<bool> ownsSessionLock() async {
    final lock = await getSessionLock();
    return lock != null && lock.tabId == _tabId;
  }
}
