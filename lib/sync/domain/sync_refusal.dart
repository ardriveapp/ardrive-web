/// Why a single-drive sync was refused before it fetched anything. See
/// `SyncCubit.lastSingleSyncRefusal`.
enum SyncRefusal {
  /// The app is running as a publication, which never syncs.
  publicationMode,

  /// Another sync is running; there is no queue behind it.
  anotherSync,

  /// An ArConnect tab without focus cannot sign.
  tabHidden,

  /// An activity that must not be interrupted, such as an upload, is running.
  activityInProgress,
}
