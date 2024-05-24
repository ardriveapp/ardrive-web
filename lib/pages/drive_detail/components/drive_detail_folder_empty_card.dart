part of '../drive_detail_page.dart';

class DriveDetailFolderEmptyCard extends StatelessWidget {
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
                  child: !isRootFolder
                      ? _emptyFolder(context)
                      : isANewUser
                          ? _newUserEmptyRootFolder(context)
                          : _existingUserEmptyRootFolder(context),
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
                content: !isRootFolder
                    ? _emptyFolder(context)
                    : isANewUser
                        ? _newUserEmptyRootFolder(context)
                        : _existingUserEmptyRootFolder(context),
              ),
            ),
          );
        });
      },
    );
  }

  Widget _emptyFolder(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final width = MediaQuery.of(context).size.width;
    return ScreenTypeLayout.builder(mobile: (context) {
      return SingleChildScrollView(
        child: Column(
          children: [
            Text(
              'Ready to organize your files?',
              style: typography.display(
                fontWeight: ArFontWeight.bold,
              ),
            ),
            Text(
              'Start by adding some content to your new folder. Explore the various options available to keep your drive neat and efficient.',
              style: typography.heading5(
                color: colorTokens.textLow,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _uploadFileCard(context),
            const SizedBox(height: 20),
            _uploadFolderCard(context),
            const SizedBox(height: 20),
            _createPinCard(context),
          ],
        ),
      );
    }, desktop: (context) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 66),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ArDriveImage(
                  image: AssetImage(Resources.images.login.confetti),
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Ready to organize your files?',
                        style: typography.display(
                          fontWeight: ArFontWeight.bold,
                        ),
                      ),
                      Text(
                        'Start by adding some content to your new folder. Explore the various options available to keep your drive neat and efficient.',
                        style: typography.heading5(
                          color: colorTokens.textLow,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                ArDriveImage(
                  image: AssetImage(Resources.images.login.confetti),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _uploadFileCard(context),
              _uploadFolderCard(context),
              if (width > SMALL_DESKTOP) _createPinCard(context),
            ],
          )
        ],
      );
    });
  }

  Widget _existingUserEmptyRootFolder(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final width = MediaQuery.of(context).size.width;

    return ScreenTypeLayout.builder(
      mobile: (context) {
        return SingleChildScrollView(
          child: Column(
            children: [
              Text(
                'Just look at this shiny new drive!',
                style: typography.heading4(
                  fontWeight: ArFontWeight.bold,
                ),
              ),
              Text(
                'When you are ready to benefit from blazingly fast, unlimited uploading, you can try out Turbo. Until then, check out some of the awesome FREE things you can do next. 👇',
                style: typography.paragraphLarge(
                  color: colorTokens.textLow,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _uploadFileCard(context),
              const SizedBox(height: 20),
              _uploadFolderCard(context),
              const SizedBox(height: 20),
              _createFolderCard(context),
              const SizedBox(height: 20),
              _createPinCard(context),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
      desktop: (context) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 66),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ArDriveImage(
                    image: AssetImage(Resources.images.login.confetti),
                  ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Just look at this shiny new drive!',
                          style: typography.display(
                            fontWeight: ArFontWeight.bold,
                          ),
                        ),
                        Text(
                          'When you are ready to benefit from blazingly fast, unlimited uploading, you can try out Turbo. Until then, check out some of the awesome FREE things you can do next. 👇',
                          style: typography.heading5(
                            color: colorTokens.textLow,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  ArDriveImage(
                    image: AssetImage(Resources.images.login.confetti),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _uploadFileCard(context),
                _uploadFolderCard(context),
                if (width > SMALL_DESKTOP) _createFolderCard(context),
                if (width > LARGE_DESKTOP) _createPinCard(context),
              ],
            )
          ],
        );
      },
    );
  }

  Widget _newUserEmptyRootFolder(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ScreenTypeLayout.builder(
      mobile: (context) {
        return SingleChildScrollView(
          child: Column(
            children: [
              Text(
                'You\'re on chain!',
                style: typography.heading4(
                  fontWeight: ArFontWeight.bold,
                ),
              ),
              Text(
                'You have just made your first blockchain interaction, congrats! You can now use your new drive to manage, share, and organize just about any multimedia file.',
                style: typography.paragraphLarge(
                  color: colorTokens.textLow,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _uploadFileCard(context),
              const SizedBox(height: 20),
              _createFolderCard(context),
            ],
          ),
        );
      },
      desktop: (context) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 66),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ArDriveImage(
                    image: AssetImage(Resources.images.login.confetti),
                  ),
                  Flexible(
                    child: Column(
                      children: [
                        Text(
                          'You\'re on chain!',
                          style: typography.display(
                            fontWeight: ArFontWeight.bold,
                          ),
                        ),
                        Text(
                          'You have just made your first blockchain interaction, congrats! You can now use your new drive to manage, share, and organize just about any multimedia file.',
                          style: typography.heading5(
                            color: colorTokens.textLow,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  ArDriveImage(
                    image: AssetImage(Resources.images.login.confetti),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _uploadFileCard(context),
                _createFolderCard(context),
              ],
            )
          ],
        );
      },
    );
  }

  Widget _uploadFileCard(
    BuildContext context,
  ) {
    return _actionCard(
      context: context,
      title: 'Upload File(s)',
      description:
          'Upload a file, or a selection of files, that are collectively under 100KB into your new drive.',
      buttonText: 'Upload',
      onPressed: () {
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

  Widget _createFolderCard(
    BuildContext context,
  ) {
    return _actionCard(
      context: context,
      title: 'Create a Folder',
      description:
          'Create a new folder to organize your files. You can create as many folders as you need to keep your drive organized.',
      buttonText: 'Create Folder',
      onPressed: () {
        promptToCreateFolder(context,
            driveId: driveId, parentFolderId: parentFolderId);
      },
      icon: ArDriveIcons.iconUploadFolder1(),
    );
  }

  Widget _uploadFolderCard(
    BuildContext context,
  ) {
    return _actionCard(
      context: context,
      title: 'Upload a Folder',
      description:
          'Upload existing folders that total less than 100KB from a computer, other file storage apps, or an external HD.',
      buttonText: 'Upload Folder',
      onPressed: () {
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

  Widget _createPinCard(
    BuildContext context,
  ) {
    return _actionCard(
      context: context,
      title: 'Create a Pin',
      description:
          'Pin any permaweb file to your Drive, to create inspiration boards, recipe collections, or NFT compilations. ',
      buttonText: 'Create Pin',
      onPressed: () {
        showPinFileDialog(context: context);
      },
      icon: ArDriveIcons.pinWithCircle(),
    );
  }

  Widget _actionCard({
    required BuildContext context,
    required String title,
    required String description,
    required String buttonText,
    required Function() onPressed,
    required ArDriveIcon icon,
  }) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ArDriveCard(
      width: 248 + 35,
      height: 248 + 35,
      backgroundColor: colorTokens.containerL2,
      contentPadding: const EdgeInsets.all(31),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          icon.copyWith(size: 25),
          Text(
            title,
            style: typography.paragraphXLarge(
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: typography.paragraphNormal(
              color: colorTokens.textLow,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ArDriveButtonNew(
            text: buttonText,
            typography: typography,
            onPressed: onPressed,
            variant: ButtonVariant.secondary,
          )
        ],
      ),
    );
  }
}
