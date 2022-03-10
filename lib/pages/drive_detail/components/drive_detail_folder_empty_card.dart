part of '../drive_detail_page.dart';

class DriveDetailFolderEmptyCard extends StatelessWidget {
  final bool promptToAddFiles;

  const DriveDetailFolderEmptyCard({this.promptToAddFiles = false});

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: double.infinity,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Row(
                children: [
                  const Icon(Icons.folder_open),
                  const SizedBox(width: 16),
                  if (promptToAddFiles)
                    Expanded(
                      child: Text(
                        appLocalizationsOf(context).addSomeFiles,
                        style: Theme.of(context).textTheme.headline6,
                      ),
                    )
                  else
                    Text(
                      appLocalizationsOf(context).addSomeFiles,
                      style: Theme.of(context).textTheme.headline6,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
