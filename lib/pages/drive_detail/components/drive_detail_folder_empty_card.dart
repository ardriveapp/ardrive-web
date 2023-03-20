part of '../drive_detail_page.dart';

class DriveDetailFolderEmptyCard extends StatelessWidget {
  final bool promptToAddFiles;
  final String driveId;
  final String parentFolderId;

  const DriveDetailFolderEmptyCard({
    Key? key,
    this.promptToAddFiles = false,
    required this.driveId,
    required this.parentFolderId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Center(
        child: ArDriveCard(
          backgroundColor:
              ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
          height: MediaQuery.of(context).size.height - 120,
          width: double.infinity,
          content: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                appLocalizationsOf(context).addSomeFiles,
                style: ArDriveTypography.headline.headline5Regular(),
              ),
              const SizedBox(
                height: 45,
              ),
              if (promptToAddFiles)
                InkWell(
                  onTap: () {
                    promptToUpload(
                      context,
                      driveId: driveId,
                      parentFolderId: parentFolderId,
                      isFolderUpload: false,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgOnAccent,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ArDriveIcons.uploadCloud(size: 45),
                        const SizedBox(
                          height: 10,
                        ),
                        Text(
                          appLocalizationsOf(context).uploadYourFirstFile,
                          style: ArDriveTypography.headline.headline5Regular(),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}
