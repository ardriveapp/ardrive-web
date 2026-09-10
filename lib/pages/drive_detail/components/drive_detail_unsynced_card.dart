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
    return [
      // Sync This Drive
      ArDriveDropdownItem(
        // One sync at a time: `SyncCubit` refuses a second one outright, so a
        // press taken while one runs starts nothing at all - and
        // `syncCurrentDrive` used to come back from that refusal and report
        // that the sync had looked and found nothing. `isDisabled` as well as a
        // null callback, because [ArDriveDropdownItemTile] picks its colours off
        // the flag alone: without it the item looks live and does nothing, which
        // is the same silence one layer down.
        onClick: isSyncing
            ? null
            : () {
                context.read<DriveDetailCubit>().syncCurrentDrive();
              },
        content: ArDriveDropdownItemTile(
          name: appLocalizationsOf(context).syncThisDrive,
          isDisabled: isSyncing,
          icon: ArDriveIcons.refresh(size: defaultIconSize),
        ),
      ),
      // Hide (only for owner)
      if (isOwner)
        ArDriveDropdownItem(
          onClick: () {
            promptToToggleHideState(
              context,
              item: DriveDataTableItemMapper.fromDrive(
                drive,
                (_) => null,
                0,
                isOwner,
              ),
            );
          },
          content: ArDriveDropdownItemTile(
            name: drive.isHidden
                ? appLocalizationsOf(context).unhide
                : appLocalizationsOf(context).hide,
            icon: drive.isHidden
                ? ArDriveIcons.eyeOpen(size: defaultIconSize)
                : ArDriveIcons.eyeClosed(size: defaultIconSize),
          ),
        ),
      // Share Drive
      ArDriveDropdownItem(
        onClick: () {
          promptToShareDrive(
            context: context,
            drive: drive,
          );
        },
        content: ArDriveDropdownItemTile(
          name: appLocalizationsOf(context).shareDrive,
          icon: ArDriveIcons.share(size: defaultIconSize),
        ),
      ),
      // More Info
      ArDriveDropdownItem(
        onClick: () {
          final bloc = context.read<DriveDetailCubit>();
          bloc.selectDriveInfoForUnsyncedDrive(
            DriveDataTableItemMapper.fromDrive(
              drive,
              (_) => null,
              0,
              isOwner,
            ),
          );
        },
        content: ArDriveDropdownItemTile(
          name: appLocalizationsOf(context).moreInfo,
          icon: ArDriveIcons.info(size: defaultIconSize),
        ),
      ),
      // Detach Drive (for non-owners who are logged in)
      if (!isOwner && context.read<ProfileCubit>().state is ProfileLoggedIn)
        ArDriveDropdownItem(
          onClick: () {
            showDetachDriveDialog(
              context: context,
              driveID: drive.id,
              driveName: drive.name,
            );
          },
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).detachDrive,
            icon: ArDriveIcons.detach(),
          ),
        ),
    ];
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
                            .colors
                            .themeFgDefault,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        drive.name,
                        style: ArDriveTypography.body.buttonLargeBold(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault,
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
                    style: ArDriveTypography.body.buttonNormalBold(),
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

/// How wide an action tile is allowed to be.
///
/// A ceiling rather than a width. The tile used to be a fixed 283x283 box, and
/// a fixed box is a phone at 280 logical pixels with a tile hanging over the
/// edge of it.
const double _actionCardMaxWidth = 283;

/// The height an action tile has when its content is smaller than it.
///
/// The old fixed height, kept as a floor so the two tiles still match at
/// ordinary text sizes - and only as a floor. [ArDriveCard] clips
/// (`Clip.antiAlias`), so a fixed height plus a column of text that grows with
/// the reader's text scale did not overflow visibly: from about 1.3x the
/// buttons were simply laid out past the clip boundary, drawn nowhere and hit
/// by nothing. At 2.0 a press on "Sync Now" reached no callback at all.
///
/// 283 less the 31 of padding either side, so the tile's outside height is
/// unchanged where nothing has grown.
const double _actionCardMinContentHeight = _actionCardMaxWidth - 31 * 2;

/// Content card shown for drives that haven't been synced yet.
/// Matches the sleek design of DriveDetailFolderEmptyCard.
class DriveDetailUnsyncedCard extends StatelessWidget {
  final Drive drive;

  /// Whether a sync has already run against this drive and come back with
  /// nothing.
  ///
  /// The card is the same card either way - same frame, same two actions - but
  /// it does not repeat itself. Before a sync it says the drive needs one;
  /// after one that found no root metadata it says the sync ran and what it
  /// found, and the primary action stops being the button that was already
  /// pressed. Rendering the identical card twice reads as a Sync Now that did
  /// nothing.
  final bool syncFoundNothing;

  const DriveDetailUnsyncedCard({
    super.key,
    required this.drive,
    this.syncFoundNothing = false,
  });

  /// What this drive's situation is, in a headline.
  String _title(BuildContext context) => syncFoundNothing
      ? appLocalizationsOf(context).driveSyncFoundNothing
      : appLocalizationsOf(context).driveNotSynced;

  /// And what to do about it.
  String _description(BuildContext context) => syncFoundNothing
      ? appLocalizationsOf(context).driveSyncFoundNothingDescription
      : appLocalizationsOf(context).driveNotSyncedDescription;

  /// What the app did about this drive when the answer is "nothing", and why.
  ///
  /// One sync runs at a time and nothing queues behind it, so opening a drive
  /// nothing has walked while another drive is syncing starts no request at
  /// all. Left unsaid, that lands the user on a card with two unavailable
  /// buttons, nothing in flight, and no way to tell that apart from an app
  /// that has quietly stopped - the strip above the page says a sync is
  /// running, and the obvious reading is that it is this one.
  ///
  /// It says which of the two it is. It promises nothing and queues nothing:
  /// the user is told, and the decision to sync stays theirs.
  Widget _syncNotice(BuildContext context) {
    // Watched, not read: this appears and goes when a sync starts and stops.
    final syncCubit = context.watch<SyncCubit>();

    if (syncCubit.state is! SyncInProgress) {
      return const SizedBox.shrink();
    }

    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // A null drive id is a sync of every drive, which covers this one.
    final syncingDriveId = syncCubit.syncingDriveId;
    final coversThisDrive =
        syncingDriveId == null || syncingDriveId == drive.id;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        coversThisDrive
            ? appLocalizationsOf(context).driveSyncAlreadyRunningForThisDrive
            : appLocalizationsOf(context)
                .driveSyncNotStartedAnotherDriveIsSyncing,
        style: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      mobile: (context) => _buildMobileContent(context),
      desktop: (context) => _buildDesktopContent(context),
    );
  }

  Widget _buildMobileContent(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Text(
            _title(context),
            style: typography.heading4(fontWeight: ArFontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Text(
                  _description(context),
                  style: typography.paragraphLarge(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                  textAlign: TextAlign.center,
                ),
                _syncNotice(context),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSyncThisDriveCard(context),
          const SizedBox(height: 20),
          _buildSyncAllDrivesCard(context),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDesktopContent(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: ArDriveCard(
          width: double.infinity,
          backgroundColor: colorTokens.containerL1,
          // Centred where the frame has room for it, scrolled where it has
          // not - which is what a large text scale, a short window or both
          // make of the same content. The frame's own height is unchanged;
          // what changes is that its content is no longer required to fit it.
          content: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 66),
                      child: Column(
                        children: [
                          Text(
                            _title(context),
                            style: typography.display(
                              fontWeight: ArFontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _description(context),
                            style: typography.heading5(
                              color: colorTokens.textLow,
                              fontWeight: ArFontWeight.semiBold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          _syncNotice(context),
                        ],
                      ),
                    ),
                    // A Wrap, not a Row: two tiles side by side need 566px
                    // plus their gap, and a narrow desktop window or a large
                    // text scale is exactly where the second one used to be
                    // pushed off the card. Below that they stack, which is
                    // the phone layout's answer to the same problem.
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 40,
                        runSpacing: 20,
                        children: [
                          _buildSyncThisDriveCard(context),
                          _buildSyncAllDrivesCard(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The frame both action tiles share.
  ///
  /// One builder rather than two copies of the same box: the fixed height that
  /// clipped the buttons away was written twice, and a fix applied to one copy
  /// is not a fix.
  Widget _actionCard(BuildContext context, {required List<Widget> children}) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _actionCardMaxWidth),
      child: ArDriveCard(
        width: double.infinity,
        backgroundColor: colorTokens.containerL2,
        contentPadding: const EdgeInsets.all(31),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _actionCardMinContentHeight,
          ),
          // Shrink-wrapped, so the tile grows with its text instead of
          // clipping it. `spaceEvenly` still spreads the content when the
          // floor above leaves room to spread.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: children,
          ),
        ),
      ),
    );
  }

  /// Builds the "Sync This Drive" action card.
  Widget _buildSyncThisDriveCard(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    // Watched, not read: this card's action is drawn as unavailable while a
    // sync runs, so it has to be rebuilt when one starts and stops.
    final isSyncing = context.watch<SyncCubit>().state is SyncInProgress;

    return _actionCard(
      context,
      children: [
        ArDriveIcons.refresh(size: 25),
        Text(
          appLocalizationsOf(context).syncThisDrive,
          style: typography.paragraphXLarge(fontWeight: ArFontWeight.semiBold),
        ),
        const SizedBox(height: 10),
        Text(
          syncFoundNothing
              ? appLocalizationsOf(context).syncThisDriveCheckAgainDescription
              : appLocalizationsOf(context).syncThisDriveDescription,
          style: typography.paragraphNormal(
            color: colorTokens.textMid,
            fontWeight: ArFontWeight.semiBold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ArDriveButtonNew(
          // Not "Sync Now" a second time: that button has been pressed, and
          // offering it again unchanged is what made the screen read as a
          // loop. Checking again is worth doing - a drive created moments
          // ago does turn up - so the action stays, under its real name.
          text: syncFoundNothing
              ? appLocalizationsOf(context).checkAgain
              : appLocalizationsOf(context).syncNow,
          typography: typography,
          // One sync at a time: the cubit refuses a second one, and
          // `syncCurrentDrive` reads the result of the sync it thought it
          // started - so a press that was refused would come back and report
          // that the sync found nothing. `isDisabled` as well as a null
          // callback, because [ArDriveButtonNew] picks its colours off the
          // flag alone.
          isDisabled: isSyncing,
          onPressed: isSyncing
              ? null
              : () {
                  context.read<DriveDetailCubit>().syncCurrentDrive();
                },
          variant: ButtonVariant.primary,
        ),
      ],
    );
  }

  /// Builds the "Sync All Drives" action card.
  Widget _buildSyncAllDrivesCard(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    // Watched, not read: this card's action is drawn as unavailable while a
    // sync runs, so it has to be rebuilt when one starts and stops.
    final isSyncing = context.watch<SyncCubit>().state is SyncInProgress;

    return _actionCard(
      context,
      children: [
        ArDriveIcons.cloudSync(size: 25),
        Text(
          appLocalizationsOf(context).syncAllDrives,
          style: typography.paragraphXLarge(fontWeight: ArFontWeight.semiBold),
        ),
        const SizedBox(height: 10),
        Text(
          appLocalizationsOf(context).syncAllDrivesDescription,
          style: typography.paragraphNormal(
            color: colorTokens.textMid,
            fontWeight: ArFontWeight.semiBold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ArDriveButtonNew(
          text: appLocalizationsOf(context).syncAllDrives,
          typography: typography,
          // `SyncCubit.startSync` has always refused while a sync runs; this
          // is what says so.
          isDisabled: isSyncing,
          onPressed: isSyncing
              ? null
              : () {
                  context
                      .read<DriveDetailCubit>()
                      .syncAllAndRefreshCurrentDrive();
                },
          variant: ButtonVariant.secondary,
        ),
      ],
    );
  }
}
