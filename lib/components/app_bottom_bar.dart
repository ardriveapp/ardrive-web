import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.drive,
    required this.currentFolder,
    required this.driveDetailState,
  });

  final Drive drive;
  final FolderWithContents? currentFolder;
  final DriveDetailState driveDetailState;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = ArDriveTheme.of(context).themeData.backgroundColor;
    return SafeArea(
      bottom: true,
      child: Container(
        height: 87,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: ArDriveTheme.of(context)
                  .themeData
                  .colors
                  .themeFgDefault
                  .withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
            BoxShadow(color: backgroundColor, offset: const Offset(0, 2)),
            BoxShadow(color: backgroundColor, offset: const Offset(-0, 8)),
          ],
          color: ArDriveTheme.of(context).themeData.backgroundColor,
        ),
        width: MediaQuery.of(context).size.width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            NewButton(
              drive: drive,
              currentFolder: currentFolder,
              driveDetailState: driveDetailState,
            ),
          ],
        ),
      ),
    );
  }
}
