part of '../drive_detail_page.dart';

class DriveDetailFolderEmptyCard extends StatefulWidget {
  final bool promptToAddFiles;
  final String driveId;
  final String parentFolderId;
  final String folderName;
  final bool isRootFolder;

  /// A sync is still reading this drive for the first time, so the folder may
  /// be empty only so far - see `DriveDetailLoadSuccess.contentsStillArriving`.
  final bool contentsStillArriving;

  const DriveDetailFolderEmptyCard({
    super.key,
    required this.promptToAddFiles,
    required this.driveId,
    required this.parentFolderId,
    required this.folderName,
    required this.isRootFolder,
    this.contentsStillArriving = false,
  });

  @override
  State<DriveDetailFolderEmptyCard> createState() =>
      _DriveDetailFolderEmptyCardState();
}

class _DriveDetailFolderEmptyCardState
    extends State<DriveDetailFolderEmptyCard> {
  @override
  Widget build(BuildContext context) {
    // A folder read while a sync is still reading its drive may be empty only
    // because its contents have not landed yet. Offering to fill it then is
    // what made a full drive flash "Your brand new drive!", so the panel says
    // the sync is still going until there is something to show or it ends.
    if (widget.contentsStillArriving) {
      return DriveDetailSyncingCard(folderName: widget.folderName);
    }

    return buildArDriveCard(context);
  }

  Widget buildArDriveCard(BuildContext context) {
    ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Everything below is written for the drive's owner: upload buttons,
    // free-allowance copy, "Your brand new drive!". Someone who opened a
    // shared link to another person's drive can do none of that, so they are
    // told what is true for them and offered nothing they cannot use.
    if (!widget.promptToAddFiles) {
      return ScreenTypeLayout.builder(
        mobile: (context) => _ReadOnlyEmptyFolder(driveId: widget.driveId),
        // The same card the owner's empty folder sits in.
        desktop: (context) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: ArDriveCard(
              width: double.infinity,
              backgroundColor: colorTokens.containerL1,
              content: _ReadOnlyEmptyFolder(driveId: widget.driveId),
            ),
          ),
        ),
      );
    }

    return BlocBuilder<DrivesCubit, DrivesState>(
      builder: (context, state) {
        final isANewUser = (state as DrivesLoadSuccess).userDrives.length == 1;

        return ScreenTypeLayout.builder(mobile: (context) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Stack(
              children: [
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: SvgPicture.asset(
                    Resources.images.login.bannerLightMode,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: !widget.isRootFolder
                      ? _EmptyFolder(
                          driveId: widget.driveId,
                          parentFolderId: widget.parentFolderId,
                        )
                      : isANewUser
                          ? _NewUserEmptyRootFolder(
                              driveId: widget.driveId,
                              parentFolderId: widget.parentFolderId,
                            )
                          : _ExistingUserEmptyRootFolder(
                              driveId: widget.driveId,
                              parentFolderId: widget.parentFolderId,
                            ),
                ),
              ],
            ),
          );
        }, desktop: (context) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: ArDriveCard(
                width: double.infinity,
                backgroundColor: colorTokens.containerL1,
                content: !widget.isRootFolder
                    ? _EmptyFolder(
                        driveId: widget.driveId,
                        parentFolderId: widget.parentFolderId,
                      )
                    : isANewUser
                        ? _NewUserEmptyRootFolder(
                            driveId: widget.driveId,
                            parentFolderId: widget.parentFolderId,
                          )
                        : _ExistingUserEmptyRootFolder(
                            driveId: widget.driveId,
                            parentFolderId: widget.parentFolderId,
                          ),
              ),
            ),
          );
        });
      },
    );
  }
}

/// An empty folder in a drive the reader cannot write to.
///
/// While a sync is still reading the drive, "empty" may not be true yet: a
/// shared folder opened for the first time is empty right up until its files
/// arrive. So it says which of the two it is.
class _ReadOnlyEmptyFolder extends StatelessWidget {
  const _ReadOnlyEmptyFolder({required this.driveId});

  final String driveId;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final syncCubit = context.watch<SyncCubit>();
    final stillReading = SyncingDriveNotice.locksMultiSelect(
      syncCubit.state,
      syncingDriveId: syncCubit.syncingDriveId,
      syncingDriveIds: syncCubit.syncingDriveIds,
      driveId: driveId,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Text(
          stillReading
              ? appLocalizationsOf(context).readOnlyFolderStillLoading
              : appLocalizationsOf(context).readOnlyFolderEmpty,
          style: typography.heading5(
            color: colorTokens.textLow,
            fontWeight: ArFontWeight.semiBold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _EmptyFolder extends StatelessWidget {
  final String driveId;
  final String parentFolderId;

  const _EmptyFolder({
    required this.driveId,
    required this.parentFolderId,
  });

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final width = MediaQuery.of(context).size.width;
    const String headerText = 'This folder is empty';
    const String descriptionText =
        'Upload files to it, or move files here from elsewhere in your drive.';

    return PlausiblePageViewWrapper(
      pageView: PlausiblePageView.folderEmptyPage,
      child: ScreenTypeLayout.builder(
        mobile: (context) => SingleChildScrollView(
          child: Column(
            children: [
              _buildHeaderText(
                context: context,
                text: headerText,
                style: typography.display(fontWeight: ArFontWeight.bold),
              ),
              const SizedBox(height: 10),
              _buildDescriptionText(
                context: context,
                text: descriptionText,
                style: typography.heading5(
                  color: colorTokens.textLow,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
              const SizedBox(height: 20),
              _ActionCard.uploadFile(context,
                  driveId: driveId,
                  parentFolderId: parentFolderId,
                  page: PlausiblePageView.folderEmptyPage,
                  intoFolder: true),
              const SizedBox(height: 20),
              _ActionCard.uploadFolder(context,
                  driveId: driveId,
                  parentFolderId: parentFolderId,
                  page: PlausiblePageView.folderEmptyPage),
              const SizedBox(height: 20),
              _ActionCard.createPin(context,
                  page: PlausiblePageView.folderEmptyPage),
            ],
          ),
        ),
        desktop: (context) => Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // No confetti: an empty folder is not an occasion, and the
            // celebration belongs to the drive that was just made.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 66),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildHeaderText(
                    context: context,
                    text: headerText,
                    style: typography.display(fontWeight: ArFontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildDescriptionText(
                    context: context,
                    text: descriptionText,
                    style: typography.heading5(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionCard.uploadFile(context,
                    driveId: driveId,
                    parentFolderId: parentFolderId,
                    page: PlausiblePageView.folderEmptyPage,
                    intoFolder: true),
                _ActionCard.uploadFolder(context,
                    driveId: driveId,
                    parentFolderId: parentFolderId,
                    page: PlausiblePageView.folderEmptyPage),
                if (width > SMALL_DESKTOP)
                  _ActionCard.createPin(context,
                      page: PlausiblePageView.folderEmptyPage),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderText({
    required BuildContext context,
    required String text,
    required TextStyle style,
  }) {
    return Text(
      text,
      style: style,
    );
  }

  Widget _buildDescriptionText({
    required BuildContext context,
    required String text,
    required TextStyle style,
  }) {
    return Text(
      text,
      style: style,
      textAlign: TextAlign.center,
    );
  }
}

class _NewUserEmptyRootFolder extends StatelessWidget {
  final String driveId;
  final String parentFolderId;

  const _NewUserEmptyRootFolder({
    required this.driveId,
    required this.parentFolderId,
  });

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final String headerText =
        appLocalizationsOf(context).newUserEmptyDriveTitle;
    final String descriptionText = appLocalizationsOf(context)
        .newUserEmptyDriveDescription(_freeUploadLimit(context));

    return PlausiblePageViewWrapper(
      pageView: PlausiblePageView.newUserDriveEmptyPage,
      child: ScreenTypeLayout.builder(
        mobile: (context) => SingleChildScrollView(
          child: Column(
            children: [
              _buildHeaderText(
                context: context,
                text: headerText,
                style: typography.heading4(fontWeight: ArFontWeight.bold),
              ),
              const SizedBox(height: 10),
              _buildDescriptionText(
                context: context,
                text: descriptionText,
                style: typography.paragraphLarge(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold),
              ),
              const SizedBox(height: 20),
              _ActionCard.uploadFile(
                context,
                driveId: driveId,
                parentFolderId: parentFolderId,
                page: PlausiblePageView.newUserDriveEmptyPage,
                variant: ButtonVariant.primary,
                compact: true,
              ),
              const SizedBox(height: 12),
              _ActionCard.createFolder(
                context,
                driveId: driveId,
                parentFolderId: parentFolderId,
                page: PlausiblePageView.newUserDriveEmptyPage,
                variant: ButtonVariant.primary,
                compact: true,
              ),
            ],
          ),
        ),
        desktop: (context) => Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 66),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ArDriveImage(
                      image: AssetImage(Resources.images.login.confetti)),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          _buildHeaderText(
                            context: context,
                            text: headerText,
                            style: typography.display(
                                fontWeight: ArFontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          _buildDescriptionText(
                            context: context,
                            text: descriptionText,
                            style:
                                typography.heading5(color: colorTokens.textLow),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ArDriveImage(
                      image: AssetImage(Resources.images.login.confetti)),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionCard.uploadFile(context,
                    driveId: driveId,
                    parentFolderId: parentFolderId,
                    page: PlausiblePageView.newUserDriveEmptyPage,
                    variant: ButtonVariant.primary),
                _ActionCard.createFolder(context,
                    driveId: driveId,
                    parentFolderId: parentFolderId,
                    page: PlausiblePageView.newUserDriveEmptyPage,
                    variant: ButtonVariant.primary),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderText({
    required BuildContext context,
    required String text,
    required TextStyle style,
  }) {
    return Text(
      text,
      style: style,
    );
  }

  Widget _buildDescriptionText({
    required BuildContext context,
    required String text,
    required TextStyle style,
  }) {
    return Text(
      text,
      style: style,
      textAlign: TextAlign.center,
    );
  }
}

class _ExistingUserEmptyRootFolder extends StatelessWidget {
  final String driveId;
  final String parentFolderId;

  const _ExistingUserEmptyRootFolder({
    required this.driveId,
    required this.parentFolderId,
  });

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final width = MediaQuery.of(context).size.width;
    const String headerText = 'Your brand new drive!';
    final String descriptionText = appLocalizationsOf(context)
        .existingUserEmptyDriveDescription(_freeUploadLimit(context));

    return PlausiblePageViewWrapper(
      pageView: PlausiblePageView.existingUserDriveEmptyPage,
      child: ScreenTypeLayout.builder(
        mobile: (context) => SingleChildScrollView(
          child: Column(
            children: [
              _buildHeaderText(
                context: context,
                text: headerText,
                style: typography.heading4(fontWeight: ArFontWeight.bold),
              ),
              const SizedBox(height: 10),
              _buildDescriptionText(
                context: context,
                text: descriptionText,
                style: typography.paragraphLarge(
                  color: colorTokens.textLow,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
              const SizedBox(height: 20),
              _ActionCard.uploadFile(
                context,
                driveId: driveId,
                parentFolderId: parentFolderId,
                page: PlausiblePageView.existingUserDriveEmptyPage,
              ),
              const SizedBox(height: 20),
              _ActionCard.uploadFolder(context,
                  driveId: driveId,
                  parentFolderId: parentFolderId,
                  page: PlausiblePageView.existingUserDriveEmptyPage),
              const SizedBox(height: 20),
              _ActionCard.createFolder(context,
                  driveId: driveId,
                  parentFolderId: parentFolderId,
                  page: PlausiblePageView.existingUserDriveEmptyPage),
              const SizedBox(height: 20),
              _ActionCard.createPin(context,
                  page: PlausiblePageView.existingUserDriveEmptyPage),
              const SizedBox(height: 20),
            ],
          ),
        ),
        desktop: (context) => Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 66),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ArDriveImage(
                      image: AssetImage(Resources.images.login.confetti)),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildHeaderText(
                          context: context,
                          text: headerText,
                          style:
                              typography.display(fontWeight: ArFontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        _buildDescriptionText(
                          context: context,
                          text: descriptionText,
                          style: typography.heading5(
                            color: colorTokens.textLow,
                            fontWeight: ArFontWeight.semiBold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ArDriveImage(
                      image: AssetImage(Resources.images.login.confetti)),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionCard.uploadFile(context,
                    driveId: driveId,
                    parentFolderId: parentFolderId,
                    page: PlausiblePageView.existingUserDriveEmptyPage),
                _ActionCard.uploadFolder(context,
                    driveId: driveId,
                    parentFolderId: parentFolderId,
                    page: PlausiblePageView.existingUserDriveEmptyPage),
                if (width > SMALL_DESKTOP)
                  _ActionCard.createFolder(context,
                      driveId: driveId,
                      parentFolderId: parentFolderId,
                      page: PlausiblePageView.existingUserDriveEmptyPage),
                if (width > LARGE_DESKTOP)
                  _ActionCard.createPin(context,
                      page: PlausiblePageView.existingUserDriveEmptyPage),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderText({
    required BuildContext context,
    required String text,
    required TextStyle style,
  }) {
    return Text(
      text,
      style: style,
    );
  }

  Widget _buildDescriptionText({
    required BuildContext context,
    required String text,
    required TextStyle style,
  }) {
    return Text(
      text,
      style: style,
      textAlign: TextAlign.center,
    );
  }
}

class _ActionCard {
  static Widget uploadFile(
    BuildContext context, {
    required String driveId,
    required String parentFolderId,
    required PlausiblePageView page,
    ButtonVariant variant = ButtonVariant.secondary,
    bool compact = false,
    bool intoFolder = false,
  }) {
    return _buildActionCard(
      variant: variant,
      compact: compact,
      context: context,
      title: 'Upload files',
      description: intoFolder
          ? 'Upload one or more files into this folder.'
          : 'Upload one or more files into your new drive.',
      buttonText: 'Upload',
      onPressed: () {
        PlausibleEventTracker.trackClickUploadFileEmptyState(page);

        promptToUpload(
          context,
          driveId: driveId,
          parentFolderId: parentFolderId,
          isFolderUpload: false,
        );
      },
      icon: ArDriveIcons.upload(),
    );
  }

  static Widget createFolder(
    BuildContext context, {
    required String driveId,
    required String parentFolderId,
    required PlausiblePageView page,
    ButtonVariant variant = ButtonVariant.secondary,
    bool compact = false,
  }) {
    return _buildActionCard(
      variant: variant,
      compact: compact,
      context: context,
      title: 'Create a folder',
      description: 'Create folders to keep your drive organized.',
      buttonText: 'Create folder',
      onPressed: () {
        PlausibleEventTracker.trackClickCreateFolderEmptyState(page);

        promptToCreateFolder(context,
            driveId: driveId, parentFolderId: parentFolderId);
      },
      icon: ArDriveIcons.iconNewFolder1(),
    );
  }

  static Widget uploadFolder(BuildContext context,
      {required String driveId,
      required String parentFolderId,
      required PlausiblePageView page}) {
    return _buildActionCard(
      context: context,
      title: 'Upload a folder',
      description:
          'Upload existing folders from your computer, other file storage apps, or an external HD.',
      buttonText: 'Upload folder',
      onPressed: () {
        PlausibleEventTracker.trackClickUploadFolderEmptyState(page);

        promptToUpload(
          context,
          driveId: driveId,
          parentFolderId: parentFolderId,
          isFolderUpload: true,
        );
      },
      icon: ArDriveIcons.iconUploadFolder1(),
    );
  }

  static Widget createPin(BuildContext context,
      {required PlausiblePageView page}) {
    return _buildActionCard(
      context: context,
      title: 'Create a pin',
      description:
          'Pin any permaweb file to your drive, to create inspiration boards, recipe collections, or NFT galleries.',
      buttonText: 'Create pin',
      onPressed: () {
        PlausibleEventTracker.trackClickCreatePinEmptyState(page);

        showPinFileDialog(context: context);
      },
      icon: ArDriveIcons.pinWithCircle(),
    );
  }

  static Widget _buildActionCard({
    required BuildContext context,
    required String title,
    required String description,
    required String buttonText,
    required Function() onPressed,
    required ArDriveIcon icon,
    ButtonVariant variant = ButtonVariant.secondary,
    bool compact = false,
  }) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // A phone gets the same card lying down.
    //
    // Two 283px squares stacked, under a heading and a paragraph, is about
    // 800px of content on a screen that has around 600 - so the one page in
    // the product whose job is to say "well done, now do one of these two
    // things" put both of those things below the fold. Laid on its side the
    // pair takes roughly 260px and the whole page is visible at once.
    if (compact) {
      return ArDriveCard(
        backgroundColor: colorTokens.containerL2,
        contentPadding: const EdgeInsets.all(16),
        content: Row(
          children: [
            icon.copyWith(size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style:
                        typography.paragraphSmall(color: colorTokens.textMid),
                  ),
                  const SizedBox(height: 12),
                  // Under the words rather than beside them: at this width a
                  // third column leaves the description about ten characters
                  // to work with.
                  ArDriveButtonNew(
                    text: buttonText,
                    typography: typography,
                    onPressed: onPressed,
                    variant: variant,
                    size: ArDriveButtonSize.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // On a wide screen the cards sit in a row, so each is laid out from the
    // top with its button held to the bottom: icon, title and button line up
    // across the row however many lines a description takes. Spreading the
    // space evenly moved each title by half the difference in description
    // height. Stacked on a narrower screen there is no row to line up with,
    // and the spread keeps a short description from leaving a gap.
    //
    // Less padding above and below than at the sides, so the longest
    // description, Create a pin's four lines, fits with room to spare.
    final inARow =
        getDeviceType(MediaQuery.sizeOf(context)) == DeviceScreenType.desktop;

    return ArDriveCard(
      width: 283,
      height: 283,
      backgroundColor: colorTokens.containerL2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 31, vertical: 24),
      content: Column(
        mainAxisAlignment:
            inARow ? MainAxisAlignment.start : MainAxisAlignment.spaceEvenly,
        children: [
          icon.copyWith(size: 25),
          const SizedBox(height: 8),
          Text(
            title,
            style:
                typography.paragraphXLarge(fontWeight: ArFontWeight.semiBold),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: typography.paragraphNormal(
                color: colorTokens.textMid, fontWeight: ArFontWeight.semiBold),
            textAlign: TextAlign.center,
          ),
          if (inARow) const Spacer(),
          const SizedBox(height: 12),
          ArDriveButtonNew(
            size: ArDriveButtonSize.large,
            maxWidth: double.infinity,
            text: buttonText,
            typography: typography,
            onPressed: onPressed,
            variant: variant,
          ),
        ],
      ),
    );
  }
}

/// The largest file Turbo uploads free, as the uploader checks it: the limit
/// Turbo reports, or the configured one until it has. With Turbo uploads
/// turned off in config, the service provided reports no limit at all, so
/// this reads the configured one.
String _freeUploadLimit(BuildContext context) {
  final turboUploadService = context.read<TurboUploadService>();

  return filesize(turboUploadService is DontUseUploadService
      ? context.read<ConfigService>().config.allowedDataItemSizeForTurbo
      : turboUploadService.maxFreeItemSizeBytes);
}
