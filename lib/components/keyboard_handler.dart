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
import 'package:ardrive/theme/theme.dart';
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
  const KeyboardHandler({Key? key, required this.child}) : super(key: key);

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
          return RawKeyboardListener(
            focusNode: _focusTable,
            autofocus: true,
            onKey: (event) async {
              // detect if ctrl + v or cmd + v is pressed
              if (await isCtrlOrMetaKeyPressed(event)) {
                if (event is RawKeyDownEvent) {
                  setState(() => ctrlMetaPressed = true);
                }
              } else {
                setState(() => ctrlMetaPressed = false);
              }

              if (!mounted) return;
              context.read<KeyboardListenerBloc>().add(
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

Future<bool> isCtrlOrMetaKeyPressed(RawKeyEvent event) async {
  try {
    final userAgent = (await DeviceInfoPlugin().webBrowserInfo).userAgent;
    late bool ctrlMetaKeyPressed;
    if (userAgent != null && isApple(userAgent)) {
      ctrlMetaKeyPressed = event.isKeyPressed(LogicalKeyboardKey.metaLeft) ||
          event.isKeyPressed(LogicalKeyboardKey.metaRight);
    } else {
      ctrlMetaKeyPressed = event.isKeyPressed(LogicalKeyboardKey.controlLeft) ||
          event.isKeyPressed(LogicalKeyboardKey.controlRight);
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
    Key? key,
    required this.child,
    this.customShortcuts,
  }) : super(key: key);

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
    return ArDriveStandardModal(
      width: kLargeDialogWidth,
      title: 'Search Files',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          ArDriveTextField(
            controller: controller,
            label: 'Search',
            hintText: 'Search for files',
            onFieldSubmitted: (p0) => searchFiles(controller.text),
          ),
          const SizedBox(height: 16),
          ArDriveButton(
            text: 'Search',
            onPressed: () => searchFiles(controller.text),
          ),
          const SizedBox(height: 16),
          if (searchResults != null)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              width: MediaQuery.of(context).size.width * 0.5,
              child: ListView.builder(
                itemCount: searchResults!.length,
                itemBuilder: (context, index) {
                  final search = searchResults![index];

                  Widget leading;
                  ArDriveIcon trailingIcon;
                  String name;

                  if (search.result is FileRevision) {
                    leading = getIconForContentType(
                      (search.result as FileRevision).dataContentType ??
                          ContentType.octetStream,
                    );
                    name = (search.result as FileRevision).name;
                    trailingIcon = ArDriveIcons.download2();
                  } else if (search.result is FolderRevision) {
                    name = (search.result as FolderRevision).name;
                    leading = const Icon(Icons.folder);
                    trailingIcon = ArDriveIcons.newWindow();
                  } else if (search.result is DriveRevision) {
                    name = (search.result as DriveRevision).name;
                    leading = ArDriveIcons.addDrive();
                    trailingIcon = ArDriveIcons.newWindow();
                  } else {
                    throw Exception('Unknown search result type');
                  }

                  return ListTile(
                    leading: leading,
                    title: Text(
                      name,
                      style: ArDriveTypography.body.bodyBold(),
                    ),
                    trailing: ArDriveIconButton(
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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Drive: ${search.drive.name}',
                            style: ArDriveTypography.body.buttonNormalBold()),
                        if (search.folder != null)
                          Text('Folder: ${search.folder!.name}',
                              style: ArDriveTypography.body.buttonNormalBold()),
                      ],
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
