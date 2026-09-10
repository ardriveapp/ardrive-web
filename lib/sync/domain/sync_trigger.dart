/// Who asked for a sync.
///
/// Neither holds the app: a sync reports itself on the top bar's indicator,
/// which turns wherever the user already is. The distinction survives for the
/// *result*: a [userInitiated] sync ends on the shell's self-dismissing
/// summary, a [background] one - the sync on login is the only one in
/// production - on the top bar's pill, where its indicator was already
/// turning.
///
/// In its own file, out of `sync_cubit.dart`, because the sync history is
/// written to disk with this on every entry: a record the user can read back
/// after a reload cannot depend on the cubit that produced it. `SyncCubit`
/// exports it, so every existing import of `sync_cubit.dart` still sees it.
enum SyncTrigger {
  background,
  userInitiated,
}
