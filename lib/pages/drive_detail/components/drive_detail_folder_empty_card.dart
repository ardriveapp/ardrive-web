import 'package:flutter/material.dart';

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
                  Icon(Icons.folder_open),
                  Container(width: 16),
                  if (promptToAddFiles)
                    Text(
                      'There\'s nothing to see here. Click "new" to add some files.',
                      style: Theme.of(context).textTheme.headline6,
                    )
                  else
                    Text(
                      'There\'s nothing to see here.',
                      style: Theme.of(context).textTheme.headline6,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
