# Implementation Plan: Batch Process Pending Transactions

**Fix**: HIGH - Batch Process Pending Transactions
**File**: `lib/sync/domain/repositories/sync_repository.dart`
**Target Function**: `_updateTransactionStatuses` (lines 622-750)

## Current Flow

```
1. Load ALL pending transactions into Map at once (line 630-632)
2. Remove skipped transaction IDs
3. Process in batches of 5000 for GraphQL confirmations
4. Update transaction statuses in database
```

## Problem

```dart
final pendingTxMap = {
  for (final tx in await driveDao.pendingTransactions().get()) tx.id: tx,
};
```

This loads **all** pending transactions into memory at once. For active users with thousands of uploads, this can be 10-50 MB of memory.

## Proposed Solution

Load pending transactions in batches using streaming approach:

```
1. Stream pending transactions in chunks of 5000
2. Build Map incrementally as we process each chunk
3. Process confirmations for each chunk
4. Update database for each chunk
```

## Implementation

### Option A: Simple Incremental Loading (RECOMMENDED)

This is the simplest fix with minimal changes.

**Current Code** (lines 630-632):
```dart
final pendingTxMap = {
  for (final tx in await driveDao.pendingTransactions().get()) tx.id: tx,
};
```

**New Code**:
```dart
// Build map in batches to reduce memory pressure
final pendingTxMap = <String, NetworkTransaction>{};

const initialLoadBatchSize = 5000;
var offset = 0;

while (true) {
  // Query pending transactions in batches
  final batch = await (driveDao.pendingTransactions()
        ..limit(initialLoadBatchSize, offset: offset))
      .get();

  if (batch.isEmpty) break;

  // Add to map
  for (final tx in batch) {
    pendingTxMap[tx.id] = tx;
  }

  offset += initialLoadBatchSize;

  logger.d('Loaded ${pendingTxMap.length} pending transactions so far...');
}

logger.i('Loaded total of ${pendingTxMap.length} pending transactions');
```

**Pros**:
- Minimal code changes
- Map is still fully populated for remainder of function
- Easy to understand and maintain

**Cons**:
- Still builds full map in memory (just incrementally)
- Marginal improvement for memory usage

**Memory Impact**:
- Before: All loaded at once (~10-50 MB spike)
- After: Loaded in chunks (~1-5 MB at a time)
- Final state: Same (still full map in memory)

### Option B: Streaming Processing (BETTER, MORE COMPLEX)

Process pending transactions without ever building full map.

**Strategy**:
1. Query all pending transaction IDs (lightweight - just strings)
2. Remove skipped IDs
3. Process in batches of 5000:
   - Fetch full transaction objects for batch
   - Get confirmations
   - Update statuses
   - Release memory

**New Code** (replaces lines 630-750):
```dart
// First, get all pending transaction IDs (lightweight)
final allPendingTxs = await driveDao.pendingTransactions().get();
final pendingTxIds = allPendingTxs.map((tx) => tx.id).toList();

logger.i('Found ${pendingTxIds.length} pending transactions');

// Remove transactions captured in snapshots
pendingTxIds.removeWhere((id) => txsIdsToSkip.contains(id));

logger.i(
  'Skipping status update for ${txsIdsToSkip.length} transactions that were captured in snapshots',
);
logger.i('Will check status for ${pendingTxIds.length} pending transactions');

// Process in batches
const batchSize = 5000;

for (var i = 0; i < pendingTxIds.length; i += batchSize) {
  cancellationToken?.checkCancellation();

  final endIndex = (i + batchSize < pendingTxIds.length)
      ? i + batchSize
      : pendingTxIds.length;
  final batchIds = pendingTxIds.sublist(i, endIndex);

  logger.d('Processing pending transaction batch ${i ~/ batchSize + 1} (${batchIds.length} transactions)');

  // Get confirmations for this batch
  final confirmations = await arweave
      .getTransactionConfirmations(batchIds)
      .timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      logger.w('Transaction confirmation timeout for batch');
      return <String, int>{};
    },
  );

  // Fetch full transaction objects for this batch only
  final batchTxMap = <String, NetworkTransaction>{};
  for (final tx in allPendingTxs) {
    if (batchIds.contains(tx.id)) {
      batchTxMap[tx.id] = tx;
    }
  }

  // Update statuses for this batch
  await driveDao.transaction(() async {
    for (final txId in batchIds) {
      cancellationToken?.checkCancellation();

      final txConfirmations = confirmations[txId];
      if (txConfirmations == null) continue;

      final txConfirmed = txConfirmations >= kRequiredTxConfirmationCount;
      final txNotFound = txConfirmations < 0;

      String? txStatus;
      DateTime? transactionDateCreated;

      final pendingTx = batchTxMap[txId];
      if (pendingTx == null) continue;

      if (pendingTx.transactionDateCreated != null) {
        transactionDateCreated = pendingTx.transactionDateCreated!;
      } else {
        transactionDateCreated = await _getDateCreatedByDataTx(
          driveDao: driveDao,
          dataTx: txId,
        );
      }

      if (txConfirmed) {
        txStatus = TransactionStatus.confirmed;
      } else if (txNotFound) {
        final abovePendingThreshold = DateTime.now()
                .difference(pendingTx.dateCreated)
                .inMinutes >
            kRequiredTxConfirmationPendingThreshold;

        // [Rest of the status logic remains the same...]
        // Copy from lines 711-745
      }

      if (txStatus != null) {
        await driveDao.updateTransaction(
          txId,
          NetworkTransactionsCompanion(
            status: Value(txStatus),
            transactionDateCreated: Value(transactionDateCreated),
          ),
        );
      }
    }
  });

  logger.d('Completed batch ${i ~/ batchSize + 1}');
}
```

**Pros**:
- True streaming - never holds all transactions in memory
- Significant memory savings for power users
- Scales better with transaction count

**Cons**:
- More complex code changes
- Need to iterate allPendingTxs to build batch map
- Slightly more complex logic

**Memory Impact**:
- Before: All loaded at once (~10-50 MB)
- After: Only current batch (~1-5 MB max)
- **90%+ memory reduction**

## Recommendation

**Start with Option A** (Incremental Loading):
- Simpler implementation
- Lower risk
- Still provides memory improvement
- Can upgrade to Option B later if needed

**Upgrade to Option B** if:
- Users have 10,000+ pending transactions
- Memory pressure is still an issue
- Need more aggressive optimization

## Testing Strategy

### Test 1: Normal User (< 100 pending txs)
```
1. User with normal upload activity
2. Trigger sync
3. Verify:
   - Pending transactions update correctly
   - No performance regression
   - No errors
```

### Test 2: Power User (1000+ pending txs)
```
1. Perform many uploads without waiting for confirmation
2. Accumulate 1000+ pending transactions
3. Trigger sync
4. Verify:
   - All pending transactions processed
   - Memory usage is reasonable
   - No timeouts or errors
```

### Test 3: Stress Test (5000+ pending txs)
```
1. Simulate scenario with 5000+ pending transactions
2. Trigger sync
3. Monitor:
   - Memory usage (should stay low)
   - Processing time (should be reasonable)
   - Database update success rate
```

### Test 4: Cancellation
```
1. Start sync with many pending transactions
2. Cancel during pending transaction processing
3. Verify:
   - Cancellation works cleanly
   - No database corruption
   - Can resume sync later
```

## Files Modified

1. `lib/sync/domain/repositories/sync_repository.dart`
   - Modify `_updateTransactionStatuses` method (lines 630-750)

## Estimated Effort

**Option A** (Incremental Loading):
- Implementation: 30 minutes
- Testing: 1 hour
- Total: 1.5 hours

**Option B** (Streaming Processing):
- Implementation: 1-2 hours
- Testing: 2 hours
- Total: 3-4 hours

## Migration Notes

- No database changes required
- No breaking changes to API
- Fully backward compatible
- Can be deployed without data migration

## Expected Metrics

**Option A**:
- Peak memory during load: 50 MB → 5 MB (90% reduction during loading)
- Final memory: Same as before (full map still in memory)
- Processing time: Minimal change

**Option B**:
- Peak memory: 50 MB → 5 MB (90% reduction overall)
- Final memory: 50 MB → 5 MB (90% reduction sustained)
- Processing time: Potentially slightly slower due to multiple queries
