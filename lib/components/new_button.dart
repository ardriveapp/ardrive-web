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
  bool isPlusButton = false,
}) {
  final width = MediaQuery.of(context).size.width;
  final menuItems = _buildItems(
    context,
    driveDetailState: driveDetailState,
    profileState: profileState,
    drivesState: drivesState,
  );
  double menuHeight = 0;
  for (var element in menuItems) {
    menuHeight += element.height;
  }
  const menuMargin = 2 * 16.0 + 2;
  final offset = isPlusButton ? Offset(-2, -menuHeight - 80) : Offset.zero;
  final constraints = isPlusButton
      ? BoxConstraints.tightForFinite(width: width - 2 * menuMargin)
      : null;
  return PopupMenuButtonRotable<Function>(
    constraints: constraints,
    offset: offset,
    onSelected: (callback) => callback(context),
    itemBuilder: (context) => menuItems,
    rotable: isPlusButton,
    child: button,
  );
}

// TODO: use the showMenu method instead of a custom PopupMenuButtonRotable.
// See: PE-2314
class PopupMenuButtonRotable<T> extends StatefulWidget {
  final bool _rotable;

  final PopupMenuItemBuilder<T> itemBuilder;
  final T? initialValue;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final double? elevation;
  final EdgeInsetsGeometry padding;
  final double? splashRadius;
  final Widget? child;
  final Widget? icon;
  final Offset offset;
  final bool enabled;
  final ShapeBorder? shape;
  final Color? color;
  final bool? enableFeedback;
  final double? iconSize;
  final BoxConstraints? constraints;
  final PopupMenuPosition position;

  const PopupMenuButtonRotable({
    bool rotable = false,
    Key? key,
    required this.itemBuilder,
    this.initialValue,
    this.onSelected,
    this.onCanceled,
    this.tooltip,
    this.elevation,
    this.padding = const EdgeInsets.all(8.0),
    this.child,
    this.splashRadius,
    this.icon,
    this.iconSize,
    this.offset = Offset.zero,
    this.enabled = true,
    this.shape,
    this.color,
    this.enableFeedback,
    this.constraints,
    this.position = PopupMenuPosition.over,
  })  : _rotable = rotable,
        super(key: key);

  @override
  PopupMenuButtonRotableState<T> createState() =>
      PopupMenuButtonRotableState<T>();
}

class PopupMenuButtonRotableState<T> extends State<PopupMenuButtonRotable<T>> {
  bool _opened = false;

  final double _kDefaultIconSize = 24.0;

  void showButtonMenu() {
    setState(() {
      _opened = true;
    });
    final PopupMenuThemeData popupMenuTheme = PopupMenuTheme.of(context);
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final Offset offset;
    switch (widget.position) {
      case PopupMenuPosition.over:
        offset = widget.offset;
        break;
      case PopupMenuPosition.under:
        offset =
            Offset(0.0, button.size.height - (widget.padding.vertical / 2)) +
                widget.offset;
        break;
    }
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(offset, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero) + offset,
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final List<PopupMenuEntry<T>> items = widget.itemBuilder(context);
    // Only show the menu if there is something to show
    if (items.isNotEmpty) {
      showMenu<T?>(
        context: context,
        elevation: widget.elevation ?? popupMenuTheme.elevation,
        items: items,
        initialValue: widget.initialValue,
        position: position,
        shape: widget.shape ?? popupMenuTheme.shape,
        color: widget.color ?? popupMenuTheme.color,
        constraints: widget.constraints,
      ).then<void>((T? newValue) {
        setState(() {
          _opened = false;
        });
        if (!mounted) return null;
        if (newValue == null) {
          widget.onCanceled?.call();
          return null;
        }
        widget.onSelected?.call(newValue);
      });
    }
  }

  bool get _canRequestFocus {
    final NavigationMode mode = MediaQuery.maybeOf(context)?.navigationMode ??
        NavigationMode.traditional;
    switch (mode) {
      case NavigationMode.traditional:
        return widget.enabled;
      case NavigationMode.directional:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final IconThemeData iconTheme = IconTheme.of(context);
    final bool enableFeedback = widget.enableFeedback ??
        PopupMenuTheme.of(context).enableFeedback ??
        true;

    assert(debugCheckHasMaterialLocalizations(context));

    Widget w;

    if (widget.child != null) {
      w = Tooltip(
        message:
            widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
        child: InkWell(
          onTap: widget.enabled ? showButtonMenu : null,
          canRequestFocus: _canRequestFocus,
          radius: widget.splashRadius,
          enableFeedback: enableFeedback,
          child: widget.child,
        ),
      );
    } else {
      w = IconButton(
        icon: widget.icon ?? Icon(Icons.adaptive.more),
        padding: widget.padding,
        splashRadius: widget.splashRadius,
        iconSize: widget.iconSize ?? iconTheme.size ?? _kDefaultIconSize,
        tooltip:
            widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
        onPressed: widget.enabled ? showButtonMenu : null,
        enableFeedback: enableFeedback,
      );
    }

    final double turns = widget._rotable && _opened ? .12 : 0;
    return AnimatedRotation(
      turns: turns,
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticIn,
      child: w,
    );
  }
}

List<PopupMenuEntry<Function>> _buildItems(
  BuildContext context, {
  required DrivesState drivesState,
  required ProfileState profileState,
  required DriveDetailState driveDetailState,
}) {
  if (profileState.runtimeType == ProfileLoggedIn) {
    final minimumWalletBalance = BigInt.from(10000000);
    final profile = profileState as ProfileLoggedIn;
    final hasMinBalance = profile.walletBalance >= minimumWalletBalance;
    return [
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
      parentFolderId: state.folderInView.folder.id,
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
      parentFolderId: state.folderInView.folder.id,
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
