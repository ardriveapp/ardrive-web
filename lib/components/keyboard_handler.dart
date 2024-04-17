import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/dev_tools/shortcut_handler.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
// ignore: depend_on_referenced_packages
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class KeyboardHandler extends StatefulWidget {
  final Widget child;
  const KeyboardHandler({super.key, required this.child});

  @override
  State<KeyboardHandler> createState() => _KeyboardHandlerState();
}

class _KeyboardHandlerState extends State<KeyboardHandler> {
  final _focusTable = FocusNode();
  bool ctrlMetaPressed = false;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => KeyboardListenerBloc(),
      child: BlocBuilder<KeyboardListenerBloc, KeyboardListenerState>(
        builder: (context, state) {
          final keyboardListenerBloc = context.read<KeyboardListenerBloc>();
          return KeyboardListener(
            focusNode: _focusTable,
            autofocus: true,
            onKeyEvent: (event) async {
              // detect if ctrl + v or cmd + v is pressed
              if (await isCtrlOrMetaKeyPressed(event)) {
                if (event is KeyDownEvent) {
                  setState(() => ctrlMetaPressed = true);
                }
              } else {
                setState(() => ctrlMetaPressed = false);
              }

              if (!mounted) return;
              keyboardListenerBloc.add(
                KeyboardListenerUpdateCtrlMetaPressed(
                  isPressed: ctrlMetaPressed,
                ),
              );
            },
            child: widget.child,
          );
        },
      ),
    );
  }
}

Future<bool> isCtrlOrMetaKeyPressed(KeyEvent event) async {
  try {
    final userAgent = (await DeviceInfoPlugin().webBrowserInfo).userAgent;
    late bool ctrlMetaKeyPressed;
    if (userAgent != null && isApple(userAgent)) {
      ctrlMetaKeyPressed = HardwareKeyboard.instance.isMetaPressed;
    } else {
      ctrlMetaKeyPressed = HardwareKeyboard.instance.isControlPressed;
    }
    return ctrlMetaKeyPressed;
  } catch (e) {
    if (!AppPlatform.isMobile) {
      logger.e('Unable to compute platform');
    }

    return false;
  }
}

bool isApple(String userAgent) {
  const platforms = [
    'Mac',
    'iPad Simulator',
    'iPhone Simulator',
    'iPod Simulator',
    'iPad',
    'iPhone',
    'iPod',
  ];
  for (var platform in platforms) {
    if (userAgent.contains(platform)) {
      return true;
    }
  }
  return false;
}

class ArDriveDevToolsShortcuts extends StatelessWidget {
  final Widget child;
  final List<Shortcut>? customShortcuts;

  const ArDriveDevToolsShortcuts({
    super.key,
    required this.child,
    this.customShortcuts,
  });

  @override
  Widget build(BuildContext context) {
    // Define the shortcuts and their actions
    final List<Shortcut> shortcuts = [
      Shortcut(
        modifier: LogicalKeyboardKey.shiftLeft,
        key: LogicalKeyboardKey.keyQ,
        action: () {
          if (context.read<ConfigService>().flavor != Flavor.production) {
            ArDriveDevTools.instance.showDevTools();
          }
        },
      ),
      Shortcut(
        modifier: LogicalKeyboardKey.shiftLeft,
        key: LogicalKeyboardKey.keyW,
        action: () {
          if (context.read<ConfigService>().flavor != Flavor.production) {
            logger.d('Closing dev tools');
            ArDriveDevTools.instance.closeDevTools();
          }
        },
      ),
    ];

    return ShortcutHandler(
      shortcuts: shortcuts + (customShortcuts ?? []),
      child: child,
    );
  }
}

class FileSearchModal extends StatefulWidget {
  const FileSearchModal({
    super.key,
    this.initialQuery,
    required this.driveDetailCubit,
  });

  final String? initialQuery;
  final DriveDetailCubit driveDetailCubit;

  @override
  State<FileSearchModal> createState() => _FileSearchModalState();
}

class _FileSearchModalState extends State<FileSearchModal> {
  List<SearchResult>? searchResults;

  @override
  initState() {
    super.initState();
    if (widget.initialQuery != null) {
      searchFiles(widget.initialQuery!);
      controller.text = widget.initialQuery!;
    }
  }

  Future<void> searchFiles(String query) async {
    final results = await context.read<DriveDao>().searchFiles(query);
    setState(() {
      searchResults = results;
    });
  }

  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colortokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveLoginModal(
      width: MediaQuery.of(context).size.width * 0.6,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Search Files',
            style: typography.heading1(
                color: colortokens.textHigh, fontWeight: ArFontWeight.bold),
          ),
          const SizedBox(height: 16),
          ArDriveTextFieldNew(
            controller: controller,
            label: 'Search',
            hintText: 'Search for files',
            onFieldSubmitted: (p0) => searchFiles(controller.text),
          ),
          const SizedBox(height: 16),
          ArDriveButtonNew(
            text: 'Search',
            onPressed: () => searchFiles(controller.text),
            typography: typography,
            variant: ButtonVariant.primary,
          ),
          const SizedBox(height: 16),
          if (searchResults != null)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: ListView.builder(
                itemCount: searchResults!.length,
                itemBuilder: (context, index) {
                  final search = searchResults![index];

                  Widget leading;
                  Widget trailing;
                  String name;

                  if (search.result is FileRevision) {
                    leading = getIconForContentType(
                      (search.result as FileRevision).dataContentType ??
                          ContentType.octetStream,
                    );
                    name = (search.result as FileRevision).name;

                    final trailingIcon = ArDriveIcons.download2(
                      color: colortokens.iconHigh,
                    );
                    trailing = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ArDriveIconButton(
                          icon: ArDriveIcons.newWindow(),
                          onPressed: () {
                            final drivesCubit = context.read<DrivesCubit>();
                            final file = DriveDataTableItemMapper.fromRevision(
                              search.result as FileRevision,
                              true,
                            );
                            Future.delayed(const Duration(milliseconds: 300))
                                .then((value) async {
                              context
                                  .read<DrivesCubit>()
                                  .selectDrive(search.drive.id);
                              widget.driveDetailCubit.openFolder(
                                otherDriveId: file.driveId,
                                folderId: file.parentFolderId,
                              );
                              Future.delayed(const Duration(milliseconds: 500))
                                  .then(
                                (value) {
                                  widget.driveDetailCubit.selectDataItem(
                                    file,
                                    openSelectedPage: true,
                                  );
                                  Navigator.of(context).pop();
                                },
                              );
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        ArDriveIconButton(
                          icon: trailingIcon,
                          onPressed: () {
                            if (search.result is FileRevision) {
                              promptToDownloadProfileFile(
                                context: context,
                                file: DriveDataTableItemMapper.fromRevision(
                                  search.result as FileRevision,
                                  true,
                                ),
                              );
                            } else if (search.result is FolderRevision) {
                              context
                                  .read<DrivesCubit>()
                                  .selectDrive(search.drive.id);
                              widget.driveDetailCubit.openFolder(
                                otherDriveId: search.folder!.driveId,
                                folderId:
                                    (search.result as FolderRevision).folderId,
                              );
                              Navigator.of(context).pop();
                            } else if (search.result is DriveRevision) {
                              context.read<DrivesCubit>().selectDrive(
                                  (search.result as DriveRevision).driveId);
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ],
                    );
                  } else if (search.result is FolderRevision) {
                    name = (search.result as FolderRevision).name;
                    leading = Icon(
                      Icons.folder,
                      color: colortokens.iconHigh,
                    );
                    final trailingIcon = ArDriveIcons.newWindow(
                      color: colortokens.iconHigh,
                    );
                    trailing = ArDriveIconButton(
                      icon: trailingIcon,
                      onPressed: () {
                        if (search.result is FileRevision) {
                          promptToDownloadProfileFile(
                            context: context,
                            file: DriveDataTableItemMapper.fromRevision(
                              search.result as FileRevision,
                              true,
                            ),
                          );
                        } else if (search.result is FolderRevision) {
                          context
                              .read<DrivesCubit>()
                              .selectDrive(search.drive.id);
                          widget.driveDetailCubit.openFolder(
                            otherDriveId: search.folder!.driveId,
                            folderId:
                                (search.result as FolderRevision).folderId,
                          );
                          Navigator.of(context).pop();
                        } else if (search.result is DriveRevision) {
                          context.read<DrivesCubit>().selectDrive(
                              (search.result as DriveRevision).driveId);
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  } else if (search.result is DriveRevision) {
                    name = (search.result as DriveRevision).name;
                    leading = ArDriveIcons.addDrive(
                      color: colortokens.iconHigh,
                    );
                    final trailingIcon = ArDriveIcons.newWindow(
                      color: colortokens.iconHigh,
                    );
                    trailing = ArDriveIconButton(
                      icon: trailingIcon,
                      onPressed: () {
                        if (search.result is FileRevision) {
                          promptToDownloadProfileFile(
                            context: context,
                            file: DriveDataTableItemMapper.fromRevision(
                              search.result as FileRevision,
                              true,
                            ),
                          );
                        } else if (search.result is FolderRevision) {
                          context
                              .read<DrivesCubit>()
                              .selectDrive(search.drive.id);
                          widget.driveDetailCubit.openFolder(
                            otherDriveId: search.folder!.driveId,
                            folderId:
                                (search.result as FolderRevision).folderId,
                          );
                          Navigator.of(context).pop();
                        } else if (search.result is DriveRevision) {
                          context.read<DrivesCubit>().selectDrive(
                              (search.result as DriveRevision).driveId);
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  } else {
                    throw Exception('Unknown search result type');
                  }

                  return HoverWidget(
                    hoverScale: 1,
                    child: SizedBox(
                      child: ArDriveClickArea(
                        child: ListTile(
                          onTap: () {
                            if (search.result is FileRevision) {
                              promptToDownloadProfileFile(
                                context: context,
                                file: DriveDataTableItemMapper.fromRevision(
                                  search.result as FileRevision,
                                  true,
                                ),
                              );
                            } else if (search.result is FolderRevision) {
                              final drivesCubit = context.read<DrivesCubit>();
                              Navigator.pop(context);
                              Future.delayed(const Duration(milliseconds: 300))
                                  .then((value) {
                                drivesCubit.selectDrive(search.drive.id);
                                widget.driveDetailCubit.openFolder(
                                  otherDriveId: search.folder!.driveId,
                                  folderId: (search.result as FolderRevision)
                                      .folderId,
                                );
                              });
                            } else if (search.result is DriveRevision) {
                              final drivesCubit = context.read<DrivesCubit>();
                              Navigator.of(context).pop();

                              Future.delayed(const Duration(milliseconds: 300))
                                  .then((value) {
                                drivesCubit.selectDrive(
                                    (search.result as DriveRevision).driveId);
                              });
                            }
                          },
                          leading: leading,
                          title: Text(
                            name,
                            style: typography.paragraphXLarge(
                              color: colortokens.textHigh,
                              fontWeight: ArFontWeight.bold,
                            ),
                          ),
                          trailing: trailing,
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Drive: ${search.drive.name}',
                                style: typography.paragraphNormal(
                                  color: colortokens.textLow,
                                  fontWeight: ArFontWeight.semiBold,
                                ),
                              ),
                              if (search.folder != null)
                                Text(
                                  'Folder: ${search.folder!.name}',
                                  style: typography.paragraphNormal(
                                    color: colortokens.textLow,
                                    fontWeight: ArFontWeight.semiBold,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
