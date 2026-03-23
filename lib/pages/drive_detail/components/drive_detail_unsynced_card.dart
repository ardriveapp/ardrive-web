part of '../drive_detail_page.dart';

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
              child: ArDriveDropdown(
                anchor: const Aligned(
                  follower: Alignment.topRight,
                  target: Alignment.bottomRight,
                ),
                items: _buildMenuItems(context),
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

  List<ArDriveDropdownItem> _buildMenuItems(BuildContext context) {
    return [
      // Sync This Drive
      ArDriveDropdownItem(
        onClick: () {
          context.read<DriveDetailCubit>().syncCurrentDrive();
        },
        content: ArDriveDropdownItemTile(
          name: appLocalizationsOf(context).syncThisDrive,
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
          bloc.selectDataItem(
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

/// Mobile view for unsynced drive with folder navigation header and content.
class _UnsyncedDriveMobileView extends StatelessWidget {
  final Drive drive;
  final bool isOwner;

  const _UnsyncedDriveMobileView({
    required this.drive,
    required this.isOwner,
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
              ArDriveDropdown(
                anchor: const Aligned(
                  follower: Alignment.topRight,
                  target: Alignment.bottomRight,
                ),
                items: _buildMobileMenuItems(context),
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
          child: DriveDetailUnsyncedCard(drive: drive),
        ),
      ],
    );
  }

  List<ArDriveDropdownItem> _buildMobileMenuItems(BuildContext context) {
    return [
      // Sync This Drive
      ArDriveDropdownItem(
        onClick: () {
          context.read<DriveDetailCubit>().syncCurrentDrive();
        },
        content: ArDriveDropdownItemTile(
          name: appLocalizationsOf(context).syncThisDrive,
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
          bloc.selectDataItem(
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

/// Content card shown for drives that haven't been synced yet.
class DriveDetailUnsyncedCard extends StatelessWidget {
  final Drive drive;

  const DriveDetailUnsyncedCard({
    super.key,
    required this.drive,
  });

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
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            ArDriveIcons.cloudSync(size: 48, color: colorTokens.textMid),
            const SizedBox(height: 24),
            Text(
              appLocalizationsOf(context).driveNotSynced,
              style: typography.heading4(fontWeight: ArFontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              appLocalizationsOf(context).driveNotSyncedDescription,
              style: typography.paragraphLarge(
                color: colorTokens.textLow,
                fontWeight: ArFontWeight.semiBold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildSyncActionCard(context),
          ],
        ),
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
          content: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 66),
                child: Column(
                  children: [
                    ArDriveIcons.cloudSync(size: 48, color: colorTokens.textMid),
                    const SizedBox(height: 24),
                    Text(
                      appLocalizationsOf(context).driveNotSynced,
                      style: typography.display(fontWeight: ArFontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      appLocalizationsOf(context).driveNotSyncedDescription,
                      style: typography.heading5(
                        color: colorTokens.textLow,
                        fontWeight: ArFontWeight.semiBold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              _buildSyncActionCard(context),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a sync action card matching the style of other action cards in the app.
  Widget _buildSyncActionCard(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ArDriveCard(
      width: 283,
      height: 283,
      backgroundColor: colorTokens.containerL2,
      contentPadding: const EdgeInsets.all(31),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ArDriveIcons.refresh(size: 25),
          Text(
            appLocalizationsOf(context).syncThisDrive,
            style: typography.paragraphXLarge(fontWeight: ArFontWeight.semiBold),
          ),
          const SizedBox(height: 10),
          Text(
            appLocalizationsOf(context).syncThisDriveDescription,
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
              fontWeight: ArFontWeight.semiBold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ArDriveButtonNew(
            text: appLocalizationsOf(context).syncNow,
            typography: typography,
            onPressed: () {
              context.read<DriveDetailCubit>().syncCurrentDrive();
            },
            variant: ButtonVariant.primary,
          ),
        ],
      ),
    );
  }
}
