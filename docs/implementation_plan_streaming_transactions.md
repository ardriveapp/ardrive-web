# Implementation Plan: Stream-Process Transactions

**Fix**: CRITICAL - Stream-Process Transactions Instead of Loading All Into Memory
**File**: `lib/sync/domain/repositories/sync_repository.dart`
**Target Function**: `_syncDrive` (lines 780-975)

## Current Flow

```
1. Setup snapshot/GQL history sources
2. Get transactionsStream from DriveHistoryComposite
3. FETCH PHASE (lines 887-937):
   - Iterate entire stream
   - Add ALL transactions to list (memory issue)
   - Yield progress based on block heights
4. PARSE PHASE (lines 950-961):
   - Pass all transactions to _parseDriveTransactionsIntoDatabaseEntities
   - Process in batches using BatchProcessor
   - Yield progress based on entities parsed
5. Cleanup and metrics
```

## Proposed Flow

```
1. Setup snapshot/GQL history sources
2. Get transactionsStream from DriveHistoryComposite
3. STREAMING FETCH+PARSE PHASE (interleaved):
   - Maintain buffer of STREAM_CHUNK_SIZE transactions (e.g., 1000)
   - When buffer full OR stream exhausted:
     a. Process buffer via _parseDriveTransactionsIntoDatabaseEntities
     b. Clear buffer
     c. Yield combined fetch+parse progress
   - Repeat until stream exhausted
4. Cleanup and metrics
```

## Key Changes

### 1. Add Stream Chunk Size Constant
**Location**: Top of file with other constants
```dart
/// Maximum number of transactions to hold in memory during streaming sync.
/// Larger values = better throughput, higher memory usage
/// Smaller values = lower memory usage, more frequent DB commits
const kStreamTransactionChunkSize = 1000;
```

### 2. Refactor _syncDrive Method

**Current structure**:
- Fetch all (lines 887-937)
- Parse all (lines 950-961)

**New structure**:
- Stream-process in chunks (combined fetch+parse)

### 3. Progress Calculation Strategy

**Current**:
- Fetch phase: 0% → 90% (based on block heights)
- Parse phase: 90% → 100% (based on entities parsed)

**New** (need to track total expected transactions):
- Option A: Estimate total from first chunk, calculate progress as `processed / estimated`
- Option B: Use block heights for fetch progress, entity count for parse progress within each chunk
- **Recommended: Option B** - More accurate, consistent with current approach

### 4. Variables to Track

```dart
// Existing
int? firstBlockHeight;
int totalBlockHeightDifference;
double fetchPhasePercentage;

// New
int totalTransactionsProcessed = 0;
int totalTransactionsReceived = 0;
final transactionBuffer = <DriveEntityHistoryTransactionModel>[];
```

## Detailed Implementation Steps

### Step 1: Add constant and new tracking variables

**Location**: After line 785 in `_syncDrive`

```dart
// Add constant at class level (around line 120)
static const kStreamTransactionChunkSize = 1000;

// In _syncDrive function, replace line 816:
// OLD: final transactions = <DriveEntityHistoryTransactionModel>[];
// NEW:
final transactionBuffer = <DriveEntityHistoryTransactionModel>[];
int totalTransactionsProcessed = 0;
int totalTransactionsReceived = 0;
```

### Step 2: Create helper function to process transaction chunk

**Location**: After line 976 (end of _syncDrive), add new private method

```dart
Future<void> _processTransactionChunk({
  required List<DriveEntityHistoryTransactionModel> transactions,
  required Drive drive,
  required SecretKey? driveKey,
  required int currentBlockHeight,
  required int lastBlockHeight,
  required int transactionParseBatchSize,
  required SnapshotDriveHistory snapshotDriveHistory,
  required String ownerAddress,
}) async {
  if (transactions.isEmpty) return;

  logger.d('Processing chunk of ${transactions.length} transactions');

  await for (final _ in _parseDriveTransactionsIntoDatabaseEntities(
    transactions: transactions,
    drive: drive,
    driveKey: driveKey,
    currentBlockHeight: currentBlockHeight,
    lastBlockHeight: lastBlockHeight,
    batchSize: transactionParseBatchSize,
    snapshotDriveHistory: snapshotDriveHistory,
    ownerAddress: ownerAddress,
  )) {
    // Just consume the stream, we'll handle progress in main loop
  }
}
```

### Step 3: Replace fetch+parse phases with streaming loop

**Location**: Replace lines 887-961

**OLD CODE**:
```dart
/// First phase of the sync
/// Here we get all transactions from its drive.
await for (DriveEntityHistoryTransactionModel t in transactionsStream) {
  // ... cancellation check ...
  // ... progress calculation ...
  transactions.add(t);  // MEMORY ISSUE
  // ... yield progress ...
}

logger.d('Done fetching data - ${gqlDriveHistory.driveId}');
// ... timing metrics ...

try {
  yield* _parseDriveTransactionsIntoDatabaseEntities(
    transactions: transactions,  // ALL at once
    ...
  ).map((parseProgress) => parseProgress * 0.9);
}
```

**NEW CODE**:
```dart
/// Streaming phase: fetch and parse in chunks
await for (DriveEntityHistoryTransactionModel t in transactionsStream) {
  // Check for cancellation periodically
  token.checkCancellation();

  /// Initialize only once `firstBlockHeight` and `totalBlockHeightDifference`
  if (firstBlockHeight == null) {
    final block = t.transactionCommonMixin.block;
    if (block != null) {
      firstBlockHeight = block.height;
      totalBlockHeightDifference = currentBlockHeight - firstBlockHeight;
      logger.d(
        'First height: $firstBlockHeight, totalHeightDiff: $totalBlockHeightDifference',
      );
    } else {
      logger.d(
        'The transaction block is null. Transaction node id: ${t.transactionCommonMixin.id}',
      );
    }
  }

  // Add transaction to buffer
  transactionBuffer.add(t);
  totalTransactionsReceived++;

  // Process chunk when buffer is full
  if (transactionBuffer.length >= kStreamTransactionChunkSize) {
    await _processTransactionChunk(
      transactions: List.from(transactionBuffer),
      drive: drive,
      driveKey: driveKey?.key,
      currentBlockHeight: currentBlockHeight,
      lastBlockHeight: lastBlockHeight,
      transactionParseBatchSize: transactionParseBatchSize,
      snapshotDriveHistory: snapshotDriveHistory,
      ownerAddress: ownerAddress,
    );

    totalTransactionsProcessed += transactionBuffer.length;
    transactionBuffer.clear();

    logger.d('Processed $totalTransactionsProcessed / $totalTransactionsReceived transactions');
  }

  // Calculate and yield progress
  if (firstBlockHeight != null && totalBlockHeightDifference > 0) {
    final block = t.transactionCommonMixin.block;
    if (block != null) {
      fetchPhasePercentage = 1 - ((currentBlockHeight - block.height) / totalBlockHeightDifference);
    }

    // Yield progress (80% for streaming, 20% reserved for final operations)
    final streamProgress = fetchPhasePercentage * 0.8;
    yield streamProgress;
  }
}

// Process remaining transactions in buffer
if (transactionBuffer.isNotEmpty) {
  logger.d('Processing final chunk of ${transactionBuffer.length} transactions');

  await _processTransactionChunk(
    transactions: transactionBuffer,
    drive: drive,
    driveKey: driveKey?.key,
    currentBlockHeight: currentBlockHeight,
    lastBlockHeight: lastBlockHeight,
    transactionParseBatchSize: transactionParseBatchSize,
    snapshotDriveHistory: snapshotDriveHistory,
    ownerAddress: ownerAddress,
  );

  totalTransactionsProcessed += transactionBuffer.length;
  transactionBuffer.clear();
}

logger.d('Done processing all $totalTransactionsProcessed transactions - ${gqlDriveHistory.driveId}');

txFechedCallback?.call(drive.id, gqlDriveHistory.txCount);

final fetchPhaseTotalTime =
    DateTime.now().difference(fetchPhaseStartDT).inMilliseconds;

logger.d(
    'Duration of streaming phase for ${drive.name}: $fetchPhaseTotalTime ms. Processed $totalTransactionsProcessed transactions');

// Yield final progress before cleanup
yield 0.8;
```

### Step 4: Update cleanup section

**Location**: After the streaming loop (around line 967)

No changes needed - the cleanup section remains the same.

### Step 5: Update progress reporting

**Current**: Parse phase yields 0-1, mapped to 0.9 (90-100%)
**New**: Streaming phase yields 0-0.8 (0-80%), final 20% for cleanup

The progress distribution changes:
- 0% → 80%: Streaming fetch+parse
- 80% → 100%: Ghost folder creation, license sync, final operations

## Testing Strategy

### Test 1: Empty Database, Large Drive
```
1. Clear browser data / incognito
2. Login with account that has 35K item drive
3. Sync drive
4. Verify:
   - No "Array buffer allocation failed" error
   - Memory usage stays low (< 50 MB for sync)
   - Sync completes successfully
   - Progress reporting is smooth
```

### Test 2: Existing Drives, Add Large Drive
```
1. Login to account with 5-10 existing drives
2. Add new large drive (35K items)
3. Sync all drives
4. Verify:
   - No memory errors
   - Large drive syncs successfully
   - Other drives remain functional
```

### Test 3: Small Drive (Regression Test)
```
1. Sync small drive (< 100 items)
2. Verify:
   - Sync completes quickly
   - No performance regression
   - Progress reporting works
```

### Test 4: Monitor Memory
```
1. Open Chrome DevTools → Performance Monitor
2. Watch "JS Heap Size" during sync
3. Verify:
   - OLD: Spikes to 200-300 MB during large drive sync
   - NEW: Stays under 50 MB throughout sync
```

## Potential Issues & Solutions

### Issue 1: Ghost folder detection might miss folders
**Cause**: Ghost folders are tracked in `_folderIds` and `_ghostFolders` during parse phase
**Solution**: These are populated in `_addNewFileEntityRevisions` (line 1148) which is called per chunk, so should work correctly

### Issue 2: Progress might be jumpy
**Cause**: Progress based on block heights, not transaction count
**Solution**: This is expected and consistent with current behavior

### Issue 3: Sync might be slower due to more frequent commits
**Cause**: Processing 1000 transactions at a time vs all 35,000
**Solution**: This is the trade-off for lower memory. Can adjust `kStreamTransactionChunkSize` if needed (try 2000 or 5000)

## Rollback Plan

If issues arise:
1. Keep new code in separate function
2. Add feature flag: `config.useStreamingSyncProcessing`
3. If false, use old code path
4. Can toggle via config without code deployment

## Expected Metrics

**Before**:
- Peak memory: ~175 MB (transaction list)
- Database export failures on large databases

**After**:
- Peak memory: ~2-5 MB (1000 transaction chunks)
- Consistent memory usage regardless of drive size
- No export failures

## Files Modified

1. `lib/sync/domain/repositories/sync_repository.dart`
   - Add `kStreamTransactionChunkSize` constant
   - Refactor `_syncDrive` method
   - Add `_processTransactionChunk` helper method

## Estimated Effort

- Implementation: 1-2 hours
- Testing: 2-3 hours
- Total: 3-5 hours
