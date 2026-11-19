import 'package:app_settings/app_settings.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

Future<List<IOFile>> showMultipleFilesFilePickerModal(
  BuildContext context,
) {
  final io = ArDriveIO();
  return _showModal<List<IOFile>>(
      context,
      () => io.pickFiles(fileSource: FileSource.fileSystem),
      () => io.pickFiles(fileSource: FileSource.gallery),
      () async => [await (io.pickFile(fileSource: FileSource.camera))]);
}

Future<IOFile> showFilePickerModal(BuildContext context) async {
  final io = ArDriveIO();
  return _showModal<IOFile>(
      context,
      () => io.pickFile(fileSource: FileSource.fileSystem),
      () => io.pickFile(fileSource: FileSource.gallery),
      () => io.pickFile(fileSource: FileSource.camera));
}

Future<T> _showModal<T>(
  BuildContext context,
  Future<T> Function() pickFromFileSystem,
  Future<T> Function() pickFromGallery,
  Future<T> Function() pickFromCamera,
) async {
  late T content;

  await showArDriveBottomSheet<void>(context, builder: (context) {
    return _FilePickerContent<T>(
      pickFromCamera: pickFromCamera,
      pickFromFileSystem: pickFromFileSystem,
      pickFromGallery: pickFromGallery,
      onClose: (c) async {
        content = c;
      },
    );
  });
  return content;
}

class _FilePickerContent<T> extends StatefulWidget {
  const _FilePickerContent({
    super.key,
    required this.onClose,
    required this.pickFromCamera,
    required this.pickFromFileSystem,
    required this.pickFromGallery,
  });
  final Function(T) onClose;
  final Future<T> Function() pickFromFileSystem;
  final Future<T> Function() pickFromGallery;
  final Future<T> Function() pickFromCamera;

  @override
  State<_FilePickerContent<T>> createState() => __FilePickerContentState<T>();
}

class __FilePickerContentState<T> extends State<_FilePickerContent<T>> {
  bool _isLoading = false;

  /// Runs [pick] with the sheet showing it is working, then closes the sheet.
  Future<void> _run(Future<void> Function() pick) async {
    setState(() => _isLoading = true);
    await pick();
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pop(context);
    }
  }

  Widget _row({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: ArDriveFocusable(
        onActivate: onTap,
        child: ArDriveClickArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.sm),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: ArDriveSpacing.md),
                  Text(
                    label,
                    style: ArDriveTypographyNew.of(context).paragraphLarge(
                      color: colorTokens.textHigh,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    return PopScope(
        canPop: !_isLoading,
        child: ArDriveBottomSheet(
          title: l10n.uploadFiles,
          hasCloseButton: !_isLoading,
          content: _isLoading
              ? Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: ArDriveSpacing.lg),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ArDriveSpinner(size: ArDriveSpinnerSize.large),
                        const SizedBox(height: ArDriveSpacing.md),
                        Text(
                          l10n.preparingYourFiles,
                          style:
                              ArDriveTypographyNew.of(context).paragraphNormal(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colorTokens
                                .textMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _row(
                      icon: ArDriveIcons.camera1(),
                      label: l10n.camera,
                      onTap: () => _run(() async {
                        try {
                          final content = await widget.pickFromCamera();

                          widget.onClose(content);
                        } catch (e) {
                          if (e is FileSystemPermissionDeniedException) {
                            // ignore: use_build_context_synchronously
                            await _showCameraPermissionModal(context);
                            logger.e('Camera permission denied', e);
                          }
                        }
                      }),
                    ),
                    _row(
                      icon: ArDriveIcons.image(),
                      label: l10n.gallery,
                      onTap: () => _run(() async {
                        try {
                          final isEnabled =
                              await verifyStoragePermissionAndShowModalWhenDenied(
                            context,
                          );

                          if (isEnabled) {
                            final content = await widget.pickFromGallery();

                            widget.onClose(content);

                            logger.d('adding file from gallery');
                          }
                        } catch (e) {
                          logger.e('Error while picking file from gallery', e);
                        }
                      }),
                    ),
                    _row(
                      icon: ArDriveIcons.fileOutlined(),
                      label: l10n.fileSystem,
                      onTap: () => _run(() async {
                        try {
                          final isEnabled =
                              await verifyStoragePermissionAndShowModalWhenDenied(
                            context,
                          );

                          if (isEnabled) {
                            final content = await widget.pickFromFileSystem();

                            widget.onClose(content);

                            logger.d('adding file from file system');
                          }
                        } catch (e) {
                          logger.e(
                            'Error while picking file from file system',
                            e,
                          );
                        }
                      }),
                    ),
                  ],
                ),
        ));
  }
}

Future<bool> verifyStoragePermissionAndShowModalWhenDenied(
    BuildContext context) async {
  try {
    await verifyStoragePermission();
  } catch (e) {
    if (e is FileSystemPermissionDeniedException) {
      // ignore: use_build_context_synchronously
      await showStoragePermissionModal(context);
    }
    return false;
  }

  return true;
}

Future<void> showStoragePermissionModal(BuildContext context) async {
  return showArDriveDialogWithBuilder<void>(context, builder: (context) {
    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).enableStorageAccessTitle,
      description: appLocalizationsOf(context).enableStorageAccess,
      actions: [
        ModalAction.close(
          action: () {
            Navigator.pop(context);
          },
          title: appLocalizationsOf(context).cancel,
        ),
        ModalAction(
          action: () {
            AppSettings.openAppSettings();
          },
          title: appLocalizationsOf(context).goToDeviceSettings,
        ),
      ],
    );
  });
}

Future<void> _showCameraPermissionModal(BuildContext context) async {
  return showArDriveDialogWithBuilder<void>(context, builder: (context) {
    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).enableCamera,
      description: appLocalizationsOf(context).enableCameraAccess,
      actions: [
        ModalAction.close(
          action: () => Navigator.pop(context),
          title: appLocalizationsOf(context).cancel,
        ),
        ModalAction(
          action: () => AppSettings.openAppSettings(),
          title: appLocalizationsOf(context).goToDeviceSettings,
        ),
      ],
    );
  });
}
