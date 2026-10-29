part of '../drive_detail_page.dart';

/// The kebab an unsynced drive carries, in both layouts.
///
/// One menu, mounted twice. The desktop header and the phone header carried
/// byte-identical copies of these five items, which is how both of them ended
/// up with a Sync item that stayed live while a sync was running: a fix
/// applied to one copy is not a fix, because nothing in either copy says the
/// other exists.
///
/// It reads the sync state itself rather than taking it as a flag, so there
/// is no argument for a mount to pass wrongly or forget.
class UnsyncedDriveMenu extends StatelessWidget {
  const UnsyncedDriveMenu({
    super.key,
    required this.drive,
    required this.isOwner,
    required this.child,
  });

  final Drive drive;
  final bool isOwner;

  /// What the menu hangs off - a kebab, padded to suit the layout it is in.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Watched, not read: the Sync item is drawn as unavailable while a sync
    // runs, so the menu has to be rebuilt when one starts and stops.
    final isSyncing = context.watch<SyncCubit>().state is SyncInProgress;

    return ArDriveDropdown(
      anchor: const Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
      ),
      items: _items(context, isSyncing: isSyncing),
      child: child,
    );
  }

  List<ArDriveDropdownItem> _items(
    BuildContext context, {
    required bool isSyncing,
  }) {
    // The drive's one menu, for a drive this device hasn't synced: only what
    // doesn't need its contents. Sync goes through the explorer's cubit, which
    // shows the drive once it lands.
    return driveMenuItems(
      context,
      drive: drive,
      isOwner: isOwner,
      isSynced: false,
      isSyncing: isSyncing,
      onSync: () => context.read<DriveDetailCubit>().syncCurrentDrive(),
      onMoreInfo: () =>
          context.read<DriveDetailCubit>().selectDriveInfoForUnsyncedDrive(
                DriveDataTableItemMapper.fromDrive(
                  drive,
                  (_) => null,
                  0,
                  isOwner,
                ),
              ),
    );
  }
}

/// Header card for unsynced drive view with drive name and limited kebab menu.
class _UnsyncedDriveHeader extends StatelessWidget {
  final Drive drive;
  final bool isOwner;

  const _UnsyncedDriveHeader({
    required this.drive,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveCard(
      backgroundColor:
          ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      content: Row(
        children: [
          // Drive name as breadcrumb (just the root since it's unsynced)
          Expanded(
            child: Row(
              children: [
                ArDriveClickArea(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArDriveIcons.folderOutline(
                        size: 18,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colorTokens
                            .textHigh,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        drive.name,
                        style: ArDriveTypographyNew.of(context).paragraphLarge(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colorTokens
                              .textHigh,
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Kebab menu with limited options for unsynced drive
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ArDriveClickArea(
              tooltip: appLocalizationsOf(context).showMenu,
              child: UnsyncedDriveMenu(
                drive: drive,
                isOwner: isOwner,
                child: HoverWidget(
                  child: ArDriveIcons.kebabMenu(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile view for unsynced drive with folder navigation header and content.
class _UnsyncedDriveMobileView extends StatelessWidget {
  final Drive drive;
  final bool isOwner;

  /// See [DriveDetailUnsyncedCard.syncFoundNothing].
  final bool syncFoundNothing;

  const _UnsyncedDriveMobileView({
    required this.drive,
    required this.isOwner,
    this.syncFoundNothing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Mobile folder navigation header with kebab menu
        SizedBox(
          height: 45,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6),
                  child: Text(
                    drive.name,
                    style: ArDriveTypographyNew.of(context)
                        .paragraphNormal(fontWeight: ArFontWeight.semiBold),
                  ),
                ),
              ),
              UnsyncedDriveMenu(
                drive: drive,
                isOwner: isOwner,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 8,
                  ),
                  child: HoverWidget(
                    child: ArDriveIcons.kebabMenu(),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content area
        Expanded(
          child: DriveDetailUnsyncedCard(
            drive: drive,
            syncFoundNothing: syncFoundNothing,
          ),
        ),
      ],
    );
  }
}

/// What a drive that has not been synced on this device shows in place of its
/// contents: the explorer's empty state, with the two ways to sync.
///
/// Opening a drive never syncs it on its own; this is where the user decides
/// to.
class DriveDetailUnsyncedCard extends StatelessWidget {
  final Drive drive;

  /// Whether a sync has already run against this drive and come back with
  /// nothing.
  ///
  /// The same state either way, but it does not repeat itself. Before a sync
  /// it says the drive needs one; after one that found no root metadata it
  /// says so, and the main action becomes "Check again" rather than the
  /// button that was already pressed. Showing the identical state twice reads
  /// as a sync that did nothing.
  final bool syncFoundNothing;

  const DriveDetailUnsyncedCard({
    super.key,
    required this.drive,
    this.syncFoundNothing = false,
  });

  /// The line under the title.
  ///
  /// While a sync runs, the line says which sync it is instead. One sync runs
  /// at a time and nothing queues behind it, so opening a drive nothing has
  /// walked while another drive is syncing starts no request at all. Left
  /// unsaid, that is two unavailable buttons and nothing in flight, which
  /// looks like an app that has quietly stopped: the strip above the page
  /// says a sync is running, and the obvious reading is that it is this one.
  /// It promises nothing and queues nothing; the decision to sync stays the
  /// user's.
  String _message(BuildContext context, SyncCubit syncCubit) {
    final s = appLocalizationsOf(context);

    if (syncCubit.state is SyncInProgress) {
      // A null drive id is a sync of every drive, which covers this one.
      final syncingDriveId = syncCubit.syncingDriveId;
      final coversThisDrive =
          syncingDriveId == null || syncingDriveId == drive.id;

      return coversThisDrive
          ? s.driveSyncAlreadyRunningForThisDrive
          : s.driveSyncNotStartedAnotherDriveIsSyncing;
    }

    return syncFoundNothing
        ? s.driveSyncFoundNothingDescription
        : s.driveNotSyncedDescription;
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    // Watched, not read: the line changes and the actions are drawn as
    // unavailable while a sync runs, so this has to be rebuilt when one
    // starts and stops.
    final syncCubit = context.watch<SyncCubit>();
    // One sync at a time: the cubit refuses a second one, and
    // `syncCurrentDrive` reads the result of the sync it thought it started,
    // so a press that was refused would come back and report that the sync
    // found nothing. A null callback draws the button as unavailable.
    final isSyncing = syncCubit.state is SyncInProgress;

    // Centred where there is room, scrolled where there is not: a short
    // window or a large text scale.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: ArDriveEmptyState(
            icon: ArDriveIcons.cloudSync(),
            title:
                syncFoundNothing ? s.driveSyncFoundNothing : s.driveNotSynced,
            message: _message(context, syncCubit),
            // Not "Sync this drive" a second time: that button has been
            // pressed, and offering it again unchanged is what made the
            // screen read as a loop. Checking again is worth doing, since a
            // drive created moments ago does turn up, so the action stays
            // under its real name.
            actionLabel: syncFoundNothing ? s.checkAgain : s.syncThisDrive,
            onAction: isSyncing
                ? null
                : () => context.read<DriveDetailCubit>().syncCurrentDrive(),
            secondaryActionLabel: s.syncAllDrives,
            onSecondaryAction: isSyncing
                ? null
                : () => context
                    .read<DriveDetailCubit>()
                    .syncAllAndRefreshCurrentDrive(),
          ),
        ),
      ),
    );
  }
}
