part of '../drive_detail_page.dart';

class DriveDetailFolderEmptyCard extends StatefulWidget {
  final bool promptToAddFiles;
  final String driveId;
  final String parentFolderId;
  final bool isRootFolder;

  const DriveDetailFolderEmptyCard({
    super.key,
    this.promptToAddFiles = false,
    required this.driveId,
    required this.parentFolderId,
    required this.isRootFolder,
  });

  @override
  State<DriveDetailFolderEmptyCard> createState() =>
      _DriveDetailFolderEmptyCardState();
}

class _DriveDetailFolderEmptyCardState
    extends State<DriveDetailFolderEmptyCard> {
  @override
  Widget build(BuildContext context) => buildArDriveCard(context);

  Widget buildArDriveCard(BuildContext context) {
    ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
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
    const String headerText = 'Ready to organize your files?';
    const String descriptionText =
        'This folder is empty. You can move existing files into this folder, or upload new content.';

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
                  page: PlausiblePageView.folderEmptyPage),
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
                    page: PlausiblePageView.folderEmptyPage),
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

    const String headerText = 'You\'re on chain!';
    const String descriptionText =
        'You have just made your first blockchain interaction, congratulations! You can now use your new drive to manage, share, and organize just about any multimedia file. Uploads collectively under 100KB are free!';

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
    // add gesture and link to turbo
    const String descriptionText =
        'When you are ready to benefit from blazingly fast, unlimited uploading you can try out Turbo. Until then, if your upload is collectively under 100KB, here are some of the awesome FREE things you can do next.';

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
  }) {
    return _buildActionCard(
      variant: variant,
      compact: compact,
      context: context,
      title: 'Upload Files',
      description:
          'Upload a file, or a selection of files into your new drive.',
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
      title: 'Create a Folder',
      description: 'Create folders to keep your drive organized.',
      buttonText: 'Create Folder',
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
      title: 'Upload a Folder',
      description:
          'Upload existing folders from your computer, other file storage apps, or an external HD.',
      buttonText: 'Upload Folder',
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
      title: 'Create a Pin',
      description:
          'Pin any permaweb file to your drive, to create inspiration boards, recipe collections, or NFT galleries.',
      buttonText: 'Create Pin',
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
                    maxHeight: 36,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ArDriveCard(
      width: 283,
      height: 283,
      backgroundColor: colorTokens.containerL2,
      contentPadding: const EdgeInsets.all(31),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          icon.copyWith(size: 25),
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
          const SizedBox(height: 20),
          ArDriveButtonNew(
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
