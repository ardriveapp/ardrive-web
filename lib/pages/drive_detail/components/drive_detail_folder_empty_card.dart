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
  Widget build(BuildContext context) => buildArDriveCard(context);

  Widget buildArDriveCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: ArDriveCard(
        backgroundColor:
            ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
        width: double.infinity,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Flexible(
              child: SizedBox(
                height: 45,
              ),
            ),
            Text(
              appLocalizationsOf(context).noFiles,
              style: ArDriveTypography.headline.headline5Regular(),
            ),
            const Flexible(
              child: SizedBox(
                height: 45,
              ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
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
                        textAlign: TextAlign.center,
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
}
