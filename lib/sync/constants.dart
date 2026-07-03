const kBlockHeightLookBack = 240;

/// Maximum number of drives synced concurrently during a full sync.
/// Each drive sync runs its own snapshot, GraphQL pagination, and data-fetch
/// pipeline; syncing every drive at once can overwhelm the gateway (rate
/// limits) and the client. Bounded so large accounts degrade gracefully.
const kMaxConcurrentDriveSyncs = 5;
const kRequiredTxConfirmationPendingThreshold = 60 * 8;

const kArConnectSyncTimerDuration = 2;

const pendingWaitTime = Duration(days: 1);
