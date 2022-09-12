import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/create_manifest_form.dart';
import 'package:ardrive/components/drive_attach_form.dart';
import 'package:ardrive/components/drive_create_form.dart';
import 'package:ardrive/components/folder_create_form.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';

Widget buildNewButton(
  BuildContext context, {
  required Widget button,
  required DrivesState drivesState,
  required ProfileState profileState,
  required DriveDetailState driveDetailState,
  // String? title,
  bool center = false,
}) {
  final width = MediaQuery.of(context).size.width;
  // TODO: double check if it's OK to use this context, if not then build twice
  final menuItems = _buildItems(
    context,
    driveDetailState: driveDetailState,
    profileState: profileState,
    drivesState: drivesState,
    // title: title,
  );
  double menuHeight = 0;
  for (var element in menuItems) {
    menuHeight += element.height;
  }
  const menuMargin = 16.0;
  final offset = center ? Offset(menuMargin, -menuHeight - 80) : Offset.zero;
  final constraints = center
      ? BoxConstraints.tightForFinite(width: width - 2 * menuMargin)
      : null;
  return PopupMenuButton<Function>(
    constraints: constraints,
    offset: offset,
    onSelected: (callback) => callback(context),
    itemBuilder: (context) => menuItems,
    child: button,
  );
}

List<PopupMenuEntry<Function>> _buildItems(
  BuildContext context, {
  required DrivesState drivesState,
  required ProfileState profileState,
  required DriveDetailState driveDetailState,
  // String? title,
}) {
  if (profileState.runtimeType == ProfileLoggedIn) {
    final minimumWalletBalance = BigInt.from(10000000);
    final profile = profileState as ProfileLoggedIn;
    final hasMinBalance = profile.walletBalance >= minimumWalletBalance;
    return [
      // if (title != null)
      //   PopupMenuItem(
      //     enabled: false,
      //     padding: EdgeInsets.zero,
      //     child: Container(
      //       color: const Color.fromARGB(255, 220, 220, 220),
      //       padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      //       child: ListTile(
      //         title: RichText(
      //           text: TextSpan(
      //             text: title,
      //             style: const TextStyle(
      //               fontSize: 17.0,
      //               color: Colors.black,
      //             ),
      //           ),
      //         ),
      //       ),
      //     ),
      //   ),
      if (driveDetailState is DriveDetailLoadSuccess) ...{
        _buildNewFolderItem(context, driveDetailState, hasMinBalance),
        const PopupMenuDivider(key: Key('divider-1')),
        _buildUploadFileItem(context, driveDetailState, hasMinBalance),
        _buildUploadFolderItem(context, driveDetailState, hasMinBalance),
        const PopupMenuDivider(key: Key('divider-2')),
      },
      if (drivesState is DrivesLoadSuccess) ...{
        _buildCreateDrive(context, drivesState, hasMinBalance),
        _buildAttachDrive(context)
      },
      if (driveDetailState is DriveDetailLoadSuccess &&
          driveDetailState.currentDrive.privacy == 'public') ...{
        _buildCreateManifestItem(context, driveDetailState, hasMinBalance)
      },
    ];
  } else {
    return [
      // if (title != null)
      //   PopupMenuItem(
      //     enabled: false,
      //     child: Text(title),
      //   ),
      if (drivesState is DrivesLoadSuccess) ...{
        PopupMenuItem(
          value: (context) => attachDrive(context: context),
          child: ListTile(
            title: Text(appLocalizationsOf(context).attachDrive),
          ),
        ),
      }
    ];
  }
}

PopupMenuEntry<Function> _buildNewFolderItem(
  context,
  DriveDetailLoadSuccess state,
  bool hasMinBalance,
) {
  return _buildMenuItemTile(
    context: context,
    isEnabled: state.hasWritePermissions && hasMinBalance,
    itemTitle: appLocalizationsOf(context).newFolder,
    message: state.hasWritePermissions && !hasMinBalance
        ? appLocalizationsOf(context).insufficientFundsForCreateAFolder
        : null,
    value: (context) => promptToCreateFolder(
      context,
      driveId: state.currentDrive.id,
      parentFolderId: state.folderInView.folder.id,
    ),
  );
}

PopupMenuEntry<Function> _buildUploadFileItem(
  context,
  DriveDetailLoadSuccess state,
  bool hasMinBalance,
) {
  return _buildMenuItemTile(
    context: context,
    isEnabled: state.hasWritePermissions && hasMinBalance,
    message: state.hasWritePermissions && !hasMinBalance
        ? appLocalizationsOf(context).insufficientFundsForUploadFiles
        : null,
    itemTitle: appLocalizationsOf(context).uploadFiles,
    value: (context) => promptToUpload(
      context,
      driveId: state.currentDrive.id,
      folderId: state.folderInView.folder.id,
      isFolderUpload: false,
    ),
  );
}

PopupMenuEntry<Function> _buildUploadFolderItem(
  context,
  DriveDetailLoadSuccess state,
  bool hasMinBalance,
) {
  return _buildMenuItemTile(
    context: context,
    isEnabled: state.hasWritePermissions && hasMinBalance,
    itemTitle: appLocalizationsOf(context).uploadFolder,
    message: state.hasWritePermissions && !hasMinBalance
        ? appLocalizationsOf(context).insufficientFundsForUploadFolders
        : null,
    value: (context) => promptToUpload(
      context,
      driveId: state.currentDrive.id,
      folderId: state.folderInView.folder.id,
      isFolderUpload: true,
    ),
  );
}

PopupMenuEntry<Function> _buildAttachDrive(BuildContext context) {
  return PopupMenuItem(
    value: (context) => attachDrive(context: context),
    child: ListTile(
      title: Text(appLocalizationsOf(context).attachDrive),
    ),
  );
}

PopupMenuEntry<Function> _buildCreateDrive(
  BuildContext context,
  DrivesLoadSuccess drivesState,
  bool hasMinBalance,
) {
  return _buildMenuItemTile(
    context: context,
    isEnabled: drivesState.canCreateNewDrive && hasMinBalance,
    itemTitle: appLocalizationsOf(context).newDrive,
    message: hasMinBalance
        ? null
        : appLocalizationsOf(context).insufficientFundsForCreateADrive,
    value: (context) => promptToCreateDrive(context),
  );
}

PopupMenuEntry<Function> _buildCreateManifestItem(
  BuildContext context,
  DriveDetailLoadSuccess state,
  bool hasMinBalance,
) {
  return _buildMenuItemTile(
    context: context,
    isEnabled: !state.driveIsEmpty && hasMinBalance,
    itemTitle: appLocalizationsOf(context).createManifest,
    message: !state.driveIsEmpty && !hasMinBalance
        ? appLocalizationsOf(context).insufficientFundsForCreateAManifest
        : null,
    value: (context) =>
        promptToCreateManifest(context, drive: state.currentDrive),
  );
}

PopupMenuEntry<Function> _buildMenuItemTile({
  required bool isEnabled,
  Future<void> Function(dynamic)? value,
  String? message,
  required String itemTitle,
  required BuildContext context,
}) {
  return PopupMenuItem(
    value: value,
    enabled: isEnabled,
    child: Tooltip(
      message: message ?? '',
      child: ListTile(
        textColor:
            isEnabled ? ListTileTheme.of(context).textColor : Colors.grey,
        title: Text(
          itemTitle,
        ),
        enabled: isEnabled,
      ),
    ),
  );
}
