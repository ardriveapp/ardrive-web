const kBlockHeightLookBack = 240;

/// How long a transaction may go unfound before it is called failed.
///
/// Two hours, which is about sixty Arweave blocks. A transaction that has not
/// been mined in sixty blocks is not waiting its turn: either the network has
/// stalled or the bundler is having an outage, and neither resolves by being
/// waited on for longer.
///
/// This was `60 * 8` - eight hours - beside a comment claiming forty-five
/// minutes, so nobody reading it knew what it did. Eight hours also meant the
/// confirmation watch stayed awake that long for an upload already lost.
const kRequiredTxConfirmationPendingThreshold = 60 * 2;

const kArConnectSyncTimerDuration = 2;

const pendingWaitTime = Duration(days: 1);
