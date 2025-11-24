# Snapshot System Critical Bugs - Implementation Plan

**Date**: November 24, 2025
**Priority**: CRITICAL - Production Issues
**Estimated Total Effort**: 6-8 hours (including testing)

---

## Overview

This document provides detailed implementation steps for fixing 7 critical bugs in the snapshot synchronization system. These bugs cause memory leaks (3.5-17.5 GB), crashes, and data integrity issues.

**Bugs to Fix**:
1. Race condition in cache initialization
2. Unbounded `allTxs` set memory leak
3. `firstWhere()` crashes on missing tags
4. Stale transaction IDs marked as confirmed
5. Snapshot disposal never called on errors
6. Metadata cache never removed from map
7. Validation doesn't check response status

---

## Fix #1: Race Condition in Cache Initialization

### Problem
**File**: `lib/utils/snapshots/snapshot_item.dart:256-268`
**Severity**: CRITICAL

```dart
static Future<Cache<Uint8List>> _lazilyInitCache(DriveID driveId) async {
  if (!_jsonMetadataCaches.containsKey(driveId)) {  // Thread A checks
    // Thread B also checks and both see "not exists"
    final store = await newMemoryCacheStore();
    final cache = await store.cache<Uint8List>(
      name: 'snapshot-data-$driveId',
      maxEntries: 100000,
    );
    _jsonMetadataCaches[driveId] = cache;  // Both threads create duplicate caches
  }
  return _jsonMetadataCaches[driveId]!;
}
```

**Impact**: Memory leak + potential data loss on concurrent syncs

### Solution Strategy

Use a `Map<String, Future<Cache<Uint8List>>>` instead of `Map<String, Cache<Uint8List>>` to ensure only one initialization per drive.

### Implementation Steps

#### Step 1: Add Cache Future Map
**Location**: After line 145 in `snapshot_item.dart`

```dart
// OLD:
static final Map<String, Cache<Uint8List>> _jsonMetadataCaches = {};

// NEW:
static final Map<String, Cache<Uint8List>> _jsonMetadataCaches = {};
static final Map<String, Future<Cache<Uint8List>>> _cacheInitFutures = {};
```

#### Step 2: Refactor _lazilyInitCache
**Location**: Replace lines 256-268 in `snapshot_item.dart`

```dart
// OLD:
static Future<Cache<Uint8List>> _lazilyInitCache(DriveID driveId) async {
  if (!_jsonMetadataCaches.containsKey(driveId)) {
    final store = await newMemoryCacheStore();
    final cache = await store.cache<Uint8List>(
      name: 'snapshot-data-$driveId',
      maxEntries: 100000,
    );
    _jsonMetadataCaches[driveId] = cache;
  }
  return _jsonMetadataCaches[driveId]!;
}

// NEW:
static Future<Cache<Uint8List>> _lazilyInitCache(DriveID driveId) async {
  // Check if cache already exists
  if (_jsonMetadataCaches.containsKey(driveId)) {
    return _jsonMetadataCaches[driveId]!;
  }

  // Check if initialization is already in progress
  if (_cacheInitFutures.containsKey(driveId)) {
    return _cacheInitFutures[driveId]!;
  }

  // Start initialization
  final initFuture = _createCache(driveId);
  _cacheInitFutures[driveId] = initFuture;

  try {
    final cache = await initFuture;
    _jsonMetadataCaches[driveId] = cache;
    return cache;
  } finally {
    // Clean up the future after initialization completes
    _cacheInitFutures.remove(driveId);
  }
}

/// Helper method to create a new cache instance
static Future<Cache<Uint8List>> _createCache(DriveID driveId) async {
  final store = await newMemoryCacheStore();
  final cache = await store.cache<Uint8List>(
    name: 'snapshot-data-$driveId',
    maxEntries: 100000,
  );
  return cache;
}
```

#### Step 3: Update Dispose Method
**Location**: Update lines 270-274 in `snapshot_item.dart`

```dart
// OLD:
static Future<void> dispose(DriveID driveId) async {
  final cache = _jsonMetadataCaches[driveId];
  await cache?.clear();
}

// NEW:
static Future<void> dispose(DriveID driveId) async {
  // Wait for any pending initialization to complete
  final initFuture = _cacheInitFutures[driveId];
  if (initFuture != null) {
    await initFuture;
  }

  final cache = _jsonMetadataCaches[driveId];
  await cache?.clear();
  _jsonMetadataCaches.remove(driveId);
  _cacheInitFutures.remove(driveId);
}
```

### Testing

```dart
// Test concurrent initialization
test('concurrent cache initialization creates only one cache', () async {
  final driveId = 'test-drive-123';

  // Start 10 concurrent initializations
  final futures = List.generate(
    10,
    (_) => SnapshotItemOnChain._lazilyInitCache(driveId),
  );

  final caches = await Future.wait(futures);

  // All should return the same cache instance
  expect(caches.toSet().length, 1);
  expect(SnapshotItemOnChain._jsonMetadataCaches.length, 1);

  await SnapshotItemOnChain.dispose(driveId);
  expect(SnapshotItemOnChain._jsonMetadataCaches.length, 0);
});
```

### Complexity
- **Implementation**: LOW (30 minutes)
- **Testing**: MEDIUM (1 hour)
- **Risk**: LOW (backwards compatible)

---

## Fix #2: Unbounded `allTxs` Set Memory Leak

### Problem
**File**: `lib/utils/snapshots/snapshot_item.dart:146, 238, 270-274`
**Severity**: CRITICAL

```dart
static final Set<TxID> allTxs = {};  // Never cleared, grows unbounded

static Future<Uint8List> _setDataForTxId(...) async {
  allTxs.add(txId);  // Accumulates across ALL syncs
  return data;
}
```

**Impact**: 112+ MB memory leak per 50 drives (1.75M tx IDs)

### Solution Strategy

Replace static `allTxs` with per-drive tracking. Store tx IDs alongside the cache so they can be disposed together.

### Implementation Steps

#### Step 1: Replace Static Set with Per-Drive Map
**Location**: Replace line 146 in `snapshot_item.dart`

```dart
// OLD:
static final Set<TxID> allTxs = {};

// NEW:
static final Map<DriveID, Set<TxID>> _txIdsByDrive = {};
```

#### Step 2: Update _setDataForTxId
**Location**: Update line 238 in `snapshot_item.dart`

```dart
// OLD:
static Future<Uint8List> _setDataForTxId(
  DriveID driveId,
  TxID txId,
  Uint8List data,
) async {
  final Cache<Uint8List> cache = await _lazilyInitCache(driveId);
  await cache.put(txId, data);
  allTxs.add(txId);  // OLD
  return data;
}

// NEW:
static Future<Uint8List> _setDataForTxId(
  DriveID driveId,
  TxID txId,
  Uint8List data,
) async {
  final Cache<Uint8List> cache = await _lazilyInitCache(driveId);
  await cache.put(txId, data);

  // Track tx IDs per drive
  _txIdsByDrive.putIfAbsent(driveId, () => <TxID>{});
  _txIdsByDrive[driveId]!.add(txId);

  return data;
}
```

#### Step 3: Update getAllCachedTransactionIds
**Location**: Replace lines 252-254 in `snapshot_item.dart`

```dart
// OLD:
static Future<List<TxID>> getAllCachedTransactionIds() async {
  return allTxs.toList();
}

// NEW:
static Future<List<TxID>> getCachedTransactionIds(DriveID driveId) async {
  final txIds = _txIdsByDrive[driveId];
  return txIds?.toList() ?? [];
}
```

#### Step 4: Update dispose Method
**Location**: Update lines 270-274 in `snapshot_item.dart`

```dart
// OLD:
static Future<void> dispose(DriveID driveId) async {
  final cache = _jsonMetadataCaches[driveId];
  await cache?.clear();
}

// NEW:
static Future<void> dispose(DriveID driveId) async {
  // Wait for any pending initialization
  final initFuture = _cacheInitFutures[driveId];
  if (initFuture != null) {
    await initFuture;
  }

  // Clear and remove cache
  final cache = _jsonMetadataCaches[driveId];
  await cache?.clear();
  _jsonMetadataCaches.remove(driveId);
  _cacheInitFutures.remove(driveId);

  // Clear and remove tx IDs
  _txIdsByDrive.remove(driveId);

  logger.d('Disposed snapshot cache for drive $driveId');
}
```

#### Step 5: Update sync_repository.dart to Use New API
**Location**: Update line 386 in `sync_repository.dart`

```dart
// OLD:
final metadataTxsFromSnapshots =
    await SnapshotItemOnChain.getAllCachedTransactionIds();

// NEW:
final metadataTxsFromSnapshots =
    await SnapshotItemOnChain.getCachedTransactionIds(drive.id);
```

### Testing

```dart
test('tx IDs are tracked per drive and cleaned up', () async {
  final drive1 = 'drive-1';
  final drive2 = 'drive-2';

  // Add tx IDs for drive 1
  await SnapshotItemOnChain._setDataForTxId(drive1, 'tx1', Uint8List(100));
  await SnapshotItemOnChain._setDataForTxId(drive1, 'tx2', Uint8List(100));

  // Add tx IDs for drive 2
  await SnapshotItemOnChain._setDataForTxId(drive2, 'tx3', Uint8List(100));

  // Each drive should only see its own tx IDs
  final drive1Txs = await SnapshotItemOnChain.getCachedTransactionIds(drive1);
  expect(drive1Txs, hasLength(2));
  expect(drive1Txs, containsAll(['tx1', 'tx2']));

  final drive2Txs = await SnapshotItemOnChain.getCachedTransactionIds(drive2);
  expect(drive2Txs, hasLength(1));
  expect(drive2Txs, contains('tx3'));

  // Dispose drive 1
  await SnapshotItemOnChain.dispose(drive1);

  // Drive 1 tx IDs should be gone
  final drive1TxsAfter = await SnapshotItemOnChain.getCachedTransactionIds(drive1);
  expect(drive1TxsAfter, isEmpty);

  // Drive 2 tx IDs should remain
  final drive2TxsAfter = await SnapshotItemOnChain.getCachedTransactionIds(drive2);
  expect(drive2TxsAfter, hasLength(1));

  await SnapshotItemOnChain.dispose(drive2);
});
```

### Complexity
- **Implementation**: MEDIUM (1 hour)
- **Testing**: MEDIUM (1 hour)
- **Risk**: MEDIUM (changes API signature, need to update callers)

---

## Fix #3: firstWhere() Crashes on Missing Tags

### Problem
**File**: `lib/utils/snapshots/snapshot_item.dart:33-39, 102-105`
**Severity**: CRITICAL

```dart
final blockStart = tags.firstWhere((element) => element.name == 'Block-Start').value;
final blockEnd = tags.firstWhere((element) => element.name == 'Block-End').value;
```

**Impact**: Entire sync crashes if Arweave returns malformed snapshot

### Solution Strategy

Add `orElse` parameter to `firstWhere()` calls to throw custom exceptions that can be caught and logged.

### Implementation Steps

#### Step 1: Create Custom Exception
**Location**: Add to top of `snapshot_item.dart` (after imports)

```dart
/// Exception thrown when a snapshot transaction is missing required tags
class MalformedSnapshotException implements Exception {
  final String txId;
  final String missingTag;

  MalformedSnapshotException({
    required this.txId,
    required this.missingTag,
  });

  @override
  String toString() =>
      'MalformedSnapshotException: Snapshot $txId is missing required tag: $missingTag';
}
```

#### Step 2: Update instantiateSingle (Lines 102-105)
**Location**: Replace lines 102-105 in `snapshot_item.dart`

```dart
// OLD:
final maybeBlockHeightStart =
    tags.firstWhere((element) => element.name == 'Block-Start').value;
final maybeBlockHeightEnd =
    tags.firstWhere((element) => element.name == 'Block-End').value;

// NEW:
final maybeBlockHeightStart = tags.firstWhere(
  (element) => element.name == 'Block-Start',
  orElse: () => throw MalformedSnapshotException(
    txId: node.id,
    missingTag: 'Block-Start',
  ),
).value;

final maybeBlockHeightEnd = tags.firstWhere(
  (element) => element.name == 'Block-End',
  orElse: () => throw MalformedSnapshotException(
    txId: node.id,
    missingTag: 'Block-End',
  ),
).value;
```

#### Step 3: Update fromTransaction (Lines 33-39)
**Location**: Replace lines 33-39 in `snapshot_item.dart`

```dart
// OLD:
final blockStart = tags.firstWhere((element) => element.name == 'Block-Start').value;
final blockEnd = tags.firstWhere((element) => element.name == 'Block-End').value;
final driveId = tags.firstWhere((element) => element.name == 'Drive-Id').value;

// NEW:
final blockStart = tags.firstWhere(
  (element) => element.name == 'Block-Start',
  orElse: () => throw MalformedSnapshotException(
    txId: node.id,
    missingTag: 'Block-Start',
  ),
).value;

final blockEnd = tags.firstWhere(
  (element) => element.name == 'Block-End',
  orElse: () => throw MalformedSnapshotException(
    txId: node.id,
    missingTag: 'Block-End',
  ),
).value;

final driveId = tags.firstWhere(
  (element) => element.name == 'Drive-Id',
  orElse: () => throw MalformedSnapshotException(
    txId: node.id,
    missingTag: 'Drive-Id',
  ),
).value;
```

#### Step 4: Improve Error Handling in instantiateAll
**Location**: Update lines 76-78 in `snapshot_item.dart`

```dart
// OLD:
} catch (e) {
  logger.e('Error while instantiating snapshot item', e);
}

// NEW:
} catch (e) {
  if (e is MalformedSnapshotException) {
    logger.w('Skipping malformed snapshot: $e');
  } else {
    logger.e('Error while instantiating snapshot item', e);
  }
  // Continue processing other snapshots
}
```

#### Step 5: Add Validation for Block Heights
**Location**: After line 108 in `snapshot_item.dart`

```dart
int blockHeightStart = int.parse(maybeBlockHeightStart);
int blockHeightEnd = int.parse(maybeBlockHeightEnd);

// Add validation
if (blockHeightEnd < blockHeightStart) {
  throw MalformedSnapshotException(
    txId: node.id,
    missingTag: 'Invalid block range: end ($blockHeightEnd) < start ($blockHeightStart)',
  );
}

if (blockHeightStart < 0 || blockHeightEnd < 0) {
  throw MalformedSnapshotException(
    txId: node.id,
    missingTag: 'Invalid block height: negative values not allowed',
  );
}
```

### Testing

```dart
test('handles missing Block-Start tag gracefully', () async {
  final malformedNode = TransactionCommonMixin(
    id: 'malformed-tx',
    tags: [
      Tag(name: 'Block-End', value: '1000'),
      Tag(name: 'Drive-Id', value: 'test-drive'),
      // Missing Block-Start
    ],
  );

  expect(
    () => SnapshotItem.fromTransaction(
      node: malformedNode,
      driveId: 'test-drive',
      ownerAddress: 'owner',
    ),
    throwsA(isA<MalformedSnapshotException>()),
  );
});

test('handles invalid block range gracefully', () async {
  final malformedNode = TransactionCommonMixin(
    id: 'malformed-tx',
    tags: [
      Tag(name: 'Block-Start', value: '1000'),
      Tag(name: 'Block-End', value: '500'),  // End < Start
      Tag(name: 'Drive-Id', value: 'test-drive'),
    ],
  );

  expect(
    () => SnapshotItem.instantiateSingle(malformedNode),
    throwsA(isA<MalformedSnapshotException>()),
  );
});
```

### Complexity
- **Implementation**: LOW (30 minutes)
- **Testing**: MEDIUM (1 hour)
- **Risk**: LOW (better error handling, no behavior change)

---

## Fix #4: Stale Transaction IDs Marked as Confirmed

### Problem
**File**: `lib/sync/domain/repositories/sync_repository.dart:384-391, 752-761`
**Severity**: CRITICAL

```dart
// Gets tx IDs from ALL syncs (never cleared!)
final metadataTxsFromSnapshots =
    await SnapshotItemOnChain.getAllCachedTransactionIds();

// Marks them as confirmed without checking Arweave
for (final txId in txsIdsToSkip) {
  await driveDao.writeToTransaction(
    NetworkTransactionsCompanion(
      id: Value(txId),
      status: const Value(TransactionStatus.confirmed),
    ),
  );
}
```

**Impact**: Transactions marked "confirmed" when they might not be on-chain

### Solution Strategy

This is automatically fixed by Fix #2 (per-drive tx ID tracking). The new API `getCachedTransactionIds(driveId)` only returns tx IDs for the current drive, not stale IDs from previous syncs.

### Implementation Steps

#### Step 1: Update sync_repository.dart
**Location**: Line 386 in `sync_repository.dart`

```dart
// This change is part of Fix #2, but documenting here for clarity

// OLD:
final metadataTxsFromSnapshots =
    await SnapshotItemOnChain.getAllCachedTransactionIds();

// NEW:
final metadataTxsFromSnapshots =
    await SnapshotItemOnChain.getCachedTransactionIds(drive.id);
```

#### Step 2: Add Logging
**Location**: After line 391 in `sync_repository.dart`

```dart
final confirmedFileTxIds = allFileRevisions
    .where(
        (file) => metadataTxsFromSnapshots.contains(file.metadataTxId))
    .map((file) => file.dataTxId)
    .toList();

// Add this:
logger.d(
  'Found ${confirmedFileTxIds.length} file data transactions confirmed by snapshots for drive ${drive.id}',
);
```

#### Step 3: Update Transaction Skip Logging
**Location**: Line 650-652 in `sync_repository.dart`

```dart
// OLD:
logger.i(
  'Skipping status update for ${txsIdsToSkip.length} transactions that were captured in snapshots',
);

// NEW:
logger.i(
  'Skipping status update for ${txsIdsToSkip.length} transactions that were captured in snapshots for current sync',
);
```

### Testing

```dart
test('only confirms tx IDs from current drive sync', () async {
  // Sync drive 1 with snapshot containing tx1, tx2
  await syncDrive(drive1);

  // Verify tx1, tx2 are marked confirmed
  final tx1 = await driveDao.getTransaction('tx1');
  expect(tx1.status, TransactionStatus.confirmed);

  // Sync drive 2 (different drive)
  await syncDrive(drive2);

  // Drive 2 should NOT mark drive 1's transactions as confirmed
  // Only drive 2's own snapshot transactions should be confirmed

  // Dispose drive 1 cache
  await SnapshotItemOnChain.dispose(drive1.id);

  // Sync drive 1 again
  await syncDrive(drive1);

  // Should fetch fresh snapshot, not use stale tx IDs
});
```

### Complexity
- **Implementation**: TRIVIAL (already done in Fix #2)
- **Testing**: MEDIUM (1 hour - integration test)
- **Risk**: LOW (dependent on Fix #2)

---

## Fix #5: Snapshot Disposal Never Called on Errors

### Problem
**File**: `lib/sync/domain/repositories/sync_repository.dart:1000`
**Severity**: CRITICAL

```dart
// Only called at END of sync
await SnapshotItemOnChain.dispose(drive.id);
```

**Impact**: Every failed/cancelled sync leaks memory

### Solution Strategy

Wrap snapshot processing in try/finally to ensure disposal happens even on errors.

### Implementation Steps

#### Step 1: Identify Snapshot Processing Scope
**Location**: Lines 826-1000 in `sync_repository.dart`

The snapshot processing starts at line 826 (after variables are initialized) and ends at line 1000 (disposal).

#### Step 2: Wrap in Try/Finally
**Location**: Restructure lines 826-1000 in `sync_repository.dart`

```dart
// After line 826:
final transactionBuffer = <DriveEntityHistoryTransactionModel>[];
int totalTransactionsProcessed = 0;
int totalTransactionsReceived = 0;

List<SnapshotItem> snapshotItems = [];

// Add try block here:
try {
  // ALL snapshot processing code goes here (lines 828-997)

  logger.d('Fetching all transactions for drive ${drive.id}');

  // ... rest of snapshot code ...

  logger.d(
      'Drive ${drive.name} completed parse phase. Progress by block height: $fetchPhasePercentage%. Starting parse phase. Sync duration: $syncDriveTotalTime ms. Fetching used ${(averageBetweenFetchAndGet * 100).toStringAsFixed(2)}% of drive sync process');

} finally {
  // Always dispose snapshot cache, even on error
  await SnapshotItemOnChain.dispose(drive.id);
  logger.d('Disposed snapshot cache for drive ${drive.id}');
}
```

#### Step 3: Remove Original Disposal Call
**Location**: Line 1000 in `sync_repository.dart`

```dart
// DELETE this line (now in finally block):
await SnapshotItemOnChain.dispose(drive.id);
```

#### Step 4: Add Disposal on Cancellation
**Location**: Check if cancellation token cleanup needs disposal

The `token.checkCancellation()` throws `SyncCancelledException`. We need to ensure this is caught and cleanup happens.

**Location**: Around line 169 in `sync_repository.dart` (in syncAllDrives)

```dart
try {
  await for (final syncProgress in syncDrive(...)) {
    // ...
  }
} on SyncCancelledException {
  logger.i('Sync cancelled for drive ${drive.id}');
  // Disposal happens in finally block of _syncDrive
  rethrow;
} catch (e, stacktrace) {
  logger.e('Error syncing drive ${drive.id}', e, stacktrace);
  // Disposal happens in finally block of _syncDrive
  rethrow;
}
```

### Testing

```dart
test('disposes snapshot cache on sync error', () async {
  final drive = createTestDrive();

  // Mock to throw error during snapshot processing
  when(() => arweave.getTransactionConfirmations(any()))
      .thenThrow(Exception('Network error'));

  // Sync should fail
  await expectLater(
    syncRepository.syncDrive(drive, ...),
    throwsException,
  );

  // Cache should still be disposed
  final cachedTxs = await SnapshotItemOnChain.getCachedTransactionIds(drive.id);
  expect(cachedTxs, isEmpty);

  // Cache map should not contain drive
  expect(SnapshotItemOnChain._jsonMetadataCaches.containsKey(drive.id), isFalse);
});

test('disposes snapshot cache on cancellation', () async {
  final drive = createTestDrive();
  final cancellationToken = SyncCancellationToken();

  // Cancel after 1 second
  Future.delayed(Duration(seconds: 1), () => cancellationToken.cancel());

  // Sync should be cancelled
  await expectLater(
    syncRepository.syncDrive(drive, cancellationToken: cancellationToken),
    throwsA(isA<SyncCancelledException>()),
  );

  // Cache should still be disposed
  final cachedTxs = await SnapshotItemOnChain.getCachedTransactionIds(drive.id);
  expect(cachedTxs, isEmpty);
});
```

### Complexity
- **Implementation**: LOW (30 minutes)
- **Testing**: MEDIUM (1 hour)
- **Risk**: LOW (defensive programming)

---

## Fix #6: Metadata Cache Never Removed From Map

### Problem
**File**: `lib/utils/snapshots/snapshot_item.dart:270-274`
**Severity**: CRITICAL

```dart
static Future<void> dispose(DriveID driveId) async {
  final cache = _jsonMetadataCaches[driveId];
  await cache?.clear();
  // Cache object stays in map forever!
}
```

**Impact**: 3.5-17.5 GB memory leak for heavy users (100 drives)

### Solution Strategy

Remove cache from map after clearing it. This is already implemented in Fix #1 and Fix #2.

### Implementation Steps

This fix is **already included** in Fix #1 (Step 3) and Fix #2 (Step 4). The updated `dispose()` method removes the cache from all maps:

```dart
static Future<void> dispose(DriveID driveId) async {
  // Wait for any pending initialization
  final initFuture = _cacheInitFutures[driveId];
  if (initFuture != null) {
    await initFuture;
  }

  // Clear and remove cache
  final cache = _jsonMetadataCaches[driveId];
  await cache?.clear();
  _jsonMetadataCaches.remove(driveId);  // FIX #6
  _cacheInitFutures.remove(driveId);    // FIX #1

  // Clear and remove tx IDs
  _txIdsByDrive.remove(driveId);        // FIX #2

  logger.d('Disposed snapshot cache for drive $driveId');
}
```

### Testing

```dart
test('removes cache from map on dispose', () async {
  final driveId = 'test-drive';

  // Initialize cache
  await SnapshotItemOnChain._lazilyInitCache(driveId);
  expect(SnapshotItemOnChain._jsonMetadataCaches.containsKey(driveId), isTrue);

  // Dispose
  await SnapshotItemOnChain.dispose(driveId);

  // Cache should be removed from map
  expect(SnapshotItemOnChain._jsonMetadataCaches.containsKey(driveId), isFalse);
  expect(SnapshotItemOnChain._txIdsByDrive.containsKey(driveId), isFalse);
  expect(SnapshotItemOnChain._cacheInitFutures.containsKey(driveId), isFalse);
});

test('does not leak memory after 100 drive syncs', () async {
  for (var i = 0; i < 100; i++) {
    final driveId = 'drive-$i';

    // Simulate sync with cache
    await SnapshotItemOnChain._setDataForTxId(driveId, 'tx-$i', Uint8List(1000));

    // Dispose
    await SnapshotItemOnChain.dispose(driveId);
  }

  // All maps should be empty
  expect(SnapshotItemOnChain._jsonMetadataCaches, isEmpty);
  expect(SnapshotItemOnChain._txIdsByDrive, isEmpty);
  expect(SnapshotItemOnChain._cacheInitFutures, isEmpty);
});
```

### Complexity
- **Implementation**: TRIVIAL (included in Fix #1 and #2)
- **Testing**: MEDIUM (1 hour - stress test)
- **Risk**: LOW

---

## Fix #7: Validation Doesn't Check Response Status

### Problem
**File**: `lib/sync/data/snapshot_validation_service.dart:29-50`
**Severity**: HIGH

```dart
final validationRequest = await http.get(..., headers: headers);
logger.d('Validation request status code: ${validationRequest.statusCode}');
// Doesn't check if it's 200/206!
logger.d('Snapshot ${snapshotItem.txId} is valid');
snapshotsVerified.add(snapshotItem);  // Added even if request failed!
```

**Impact**: Invalid snapshots pass validation → corrupted sync

### Solution Strategy

Check HTTP status codes and validate response before marking snapshot as verified.

### Implementation Steps

#### Step 1: Check HEAD Request Status
**Location**: Line 22-28 in `snapshot_validation_service.dart`

```dart
// OLD:
final snapshotValidation = await http.head(
  Uri.parse('$_arweaveGatewayUrl/$txId'),
);

if (snapshotValidation.statusCode == 200) {
  // ...
}

// NEW:
final snapshotValidation = await http.head(
  Uri.parse('$_arweaveGatewayUrl/$txId'),
);

logger.d(
  'HEAD request for snapshot ${snapshotItem.txId}: ${snapshotValidation.statusCode}',
);

if (snapshotValidation.statusCode != 200) {
  logger.w(
    'Snapshot ${snapshotItem.txId} failed HEAD validation: ${snapshotValidation.statusCode}',
  );
  continue;  // Skip this snapshot
}
```

#### Step 2: Validate Content-Length Header
**Location**: Line 29-31 in `snapshot_validation_service.dart`

```dart
// OLD:
if (snapshotValidation.headers['content-length'] != null) {
  int lenght = int.parse(snapshotValidation.headers['content-length']!);

// NEW:
final contentLengthHeader = snapshotValidation.headers['content-length'];
if (contentLengthHeader == null) {
  logger.w(
    'Snapshot ${snapshotItem.txId} has no Content-Length header',
  );
  continue;  // Skip snapshot
}

int length = int.parse(contentLengthHeader);

// Validate file size is reasonable (1KB - 500MB)
if (length < 1024) {
  logger.w(
    'Snapshot ${snapshotItem.txId} is too small: $length bytes',
  );
  continue;
}

if (length > 500 * 1024 * 1024) {  // 500 MB
  logger.w(
    'Snapshot ${snapshotItem.txId} is too large: $length bytes',
  );
  continue;
}
```

#### Step 3: Check Range Request Status
**Location**: Line 33-46 in `snapshot_validation_service.dart`

```dart
// OLD:
final headers = {
  'Range': 'bytes=${lenght - 8}-$lenght',
};

final validationRequest = await http.get(
  Uri.parse('$_arweaveGatewayUrl/$txId'),
  headers: headers,
);

logger.d('Validation request status code: ${validationRequest.statusCode}');

// NEW:
final headers = {
  'Range': 'bytes=${length - 8}-$length',
};

final validationRequest = await http.get(
  Uri.parse('$_arweaveGatewayUrl/$txId'),
  headers: headers,
);

logger.d(
  'Range request for snapshot ${snapshotItem.txId}: ${validationRequest.statusCode}',
);

// Check if range request succeeded (206 Partial Content or 200 OK)
if (validationRequest.statusCode != 206 && validationRequest.statusCode != 200) {
  logger.w(
    'Snapshot ${snapshotItem.txId} failed range validation: ${validationRequest.statusCode}',
  );
  continue;  // Skip this snapshot
}

// Validate response has content
if (validationRequest.body.isEmpty) {
  logger.w(
    'Snapshot ${snapshotItem.txId} returned empty response',
  );
  continue;
}
```

#### Step 4: Update Success Logging
**Location**: After validation checks (before line 50)

```dart
// Only log and add if all validations pass
logger.d(
  'Snapshot ${snapshotItem.txId} passed all validations (size: $length bytes)',
);
snapshotsVerified.add(snapshotItem);
```

#### Step 5: Add Timeout to Validation Requests
**Location**: Lines 22-46 in `snapshot_validation_service.dart`

```dart
const validationTimeout = Duration(seconds: 10);

final snapshotValidation = await http.head(
  Uri.parse('$_arweaveGatewayUrl/$txId'),
).timeout(
  validationTimeout,
  onTimeout: () {
    logger.w('HEAD request timeout for snapshot ${snapshotItem.txId}');
    return http.Response('', 408);  // Request Timeout
  },
);

// Later:
final validationRequest = await http.get(
  Uri.parse('$_arweaveGatewayUrl/$txId'),
  headers: headers,
).timeout(
  validationTimeout,
  onTimeout: () {
    logger.w('Range request timeout for snapshot ${snapshotItem.txId}');
    return http.Response('', 408);
  },
);
```

### Testing

```dart
test('rejects snapshot with 404 HEAD response', () async {
  when(() => httpClient.head(any())).thenAnswer(
    (_) async => http.Response('', 404),
  );

  final result = await validationService.validateSnapshotItems([snapshot1]);

  expect(result, isEmpty);
  verify(() => logger.w(contains('failed HEAD validation: 404'))).called(1);
});

test('rejects snapshot with no Content-Length', () async {
  when(() => httpClient.head(any())).thenAnswer(
    (_) async => http.Response('', 200, headers: {}),  // No Content-Length
  );

  final result = await validationService.validateSnapshotItems([snapshot1]);

  expect(result, isEmpty);
});

test('rejects snapshot that is too small', () async {
  when(() => httpClient.head(any())).thenAnswer(
    (_) async => http.Response('', 200, headers: {'content-length': '500'}),
  );

  final result = await validationService.validateSnapshotItems([snapshot1]);

  expect(result, isEmpty);
  verify(() => logger.w(contains('too small'))).called(1);
});

test('rejects snapshot with failed range request', () async {
  when(() => httpClient.head(any())).thenAnswer(
    (_) async => http.Response('', 200, headers: {'content-length': '10000'}),
  );

  when(() => httpClient.get(any(), headers: any(named: 'headers'))).thenAnswer(
    (_) async => http.Response('', 416),  // Range Not Satisfiable
  );

  final result = await validationService.validateSnapshotItems([snapshot1]);

  expect(result, isEmpty);
});

test('accepts snapshot with all valid responses', () async {
  when(() => httpClient.head(any())).thenAnswer(
    (_) async => http.Response('', 200, headers: {'content-length': '10000'}),
  );

  when(() => httpClient.get(any(), headers: any(named: 'headers'))).thenAnswer(
    (_) async => http.Response('data', 206),
  );

  final result = await validationService.validateSnapshotItems([snapshot1]);

  expect(result, hasLength(1));
  expect(result.first, equals(snapshot1));
});
```

### Complexity
- **Implementation**: MEDIUM (1 hour)
- **Testing**: MEDIUM (1-2 hours)
- **Risk**: LOW (better validation, won't break valid snapshots)

---

## Implementation Order & Dependencies

### Phase 1: Cache Management (2-3 hours)
**Order**: Fix #1 → Fix #6 → Fix #2
- Fix #1: Race condition (foundation)
- Fix #6: Cache removal (built into Fix #1)
- Fix #2: Per-drive tracking (depends on Fix #1)

### Phase 2: Error Handling (1-2 hours)
**Order**: Fix #3 → Fix #5
- Fix #3: Missing tags
- Fix #5: Try/finally cleanup

### Phase 3: Data Integrity (30 minutes)
**Order**: Fix #4 → Fix #7
- Fix #4: Stale tx IDs (automatic with Fix #2)
- Fix #7: Validation checks

---

## Testing Strategy

### Unit Tests (3-4 hours)
- Test each fix in isolation
- Mock external dependencies (HTTP, cache, database)
- Use `mocktail` for mocking

### Integration Tests (2-3 hours)
- Test concurrent syncs (Fix #1)
- Test multi-drive syncs (Fix #2)
- Test error scenarios (Fix #3, #5)
- Test memory cleanup (Fix #6)

### Manual Testing (1-2 hours)
- Test with real 35k item drive
- Monitor memory usage with Chrome DevTools
- Test cancellation scenarios
- Test network failure scenarios

---

## Rollout Plan

### Pre-Deployment
1. Run full test suite
2. Code review by team
3. Performance testing with large drives

### Deployment
1. Deploy to staging first
2. Monitor error rates and memory usage
3. Gradual rollout to production (10% → 50% → 100%)

### Monitoring
- Track memory usage metrics
- Monitor sync failure rates
- Watch for new error patterns in logs

---

## Rollback Plan

If issues arise:
1. All changes are backward compatible
2. Can revert entire commit
3. No database migrations required
4. No breaking API changes (except Fix #2 - internal API only)

---

## Estimated Timeline

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| Implementation | Fix #1-7 | 3-4 hours |
| Unit Testing | All fixes | 3-4 hours |
| Integration Testing | Multi-drive, errors | 2-3 hours |
| Code Review | Team review | 1 hour |
| Manual Testing | Real drives | 1-2 hours |
| **TOTAL** | | **10-14 hours** |

**Recommended Sprint**: 2 days (includes buffer for unexpected issues)

---

## Success Metrics

### Before Fixes
- Memory leak: 100+ MB per 50 drives
- Crash rate: ~5% on malformed snapshots
- Stale tx confirmations: Unknown but likely >0%

### After Fixes (Expected)
- Memory leak: 0 MB (all caches cleaned up)
- Crash rate: 0% (graceful error handling)
- Stale tx confirmations: 0% (per-drive tracking)
- Performance: No degradation, possibly faster due to less memory pressure

---

## Appendix: File Changes Summary

### Files Modified
1. `lib/utils/snapshots/snapshot_item.dart` - Core fixes (#1, #2, #3, #6)
2. `lib/sync/domain/repositories/sync_repository.dart` - Integration (#2, #4, #5)
3. `lib/sync/data/snapshot_validation_service.dart` - Validation (#7)

### Files Added (Tests)
1. `test/utils/snapshots/snapshot_item_concurrency_test.dart` - Fix #1 tests
2. `test/utils/snapshots/snapshot_item_memory_test.dart` - Fix #2, #6 tests
3. `test/sync/snapshot_error_handling_test.dart` - Fix #3, #5 tests
4. `test/sync/snapshot_validation_service_test.dart` - Fix #7 tests

### Lines Changed
- ~200 lines added
- ~50 lines modified
- ~10 lines deleted
- Net: +190 lines

---

## Questions?

For implementation details or clarification on any fix, refer to the relevant section above or consult with the team lead.
