import 'package:ardrive/main.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:universal_html/html.dart' as html;

class ArDriveAppWithDevTools extends StatelessWidget {
  const ArDriveAppWithDevTools({
    super.key,
    required this.widget,
  });

  final Widget widget;

  @override
  Widget build(BuildContext context) {
    return Overlay(
      key: overlayKey,
      initialEntries: [
        OverlayEntry(
          builder: (context) => widget,
        )
      ],
    );
  }
}

class AppConfigWindowManager extends StatefulWidget {
  const AppConfigWindowManager({super.key});

  @override
  State<AppConfigWindowManager> createState() => AppConfigWindowManagerState();
}

class AppConfigWindowManagerState extends State<AppConfigWindowManager> {
  final _windowTitle = ValueNotifier('Dev Tools');

  @override
  Widget build(BuildContext context) {
    final settings = context.read<ConfigService>().config;
    final configService = context.read<ConfigService>();

    ArDriveDevToolOption defaultArweaveGatewayUrlOption = ArDriveDevToolOption(
      name: 'defaultArweaveGatewayUrl',
      value: settings.defaultArweaveGatewayUrl,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            settings.copyWith(defaultArweaveGatewayUrl: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.text,
    );

    ArDriveDevToolOption useTurboOption = ArDriveDevToolOption(
      name: 'useTurbo',
      value: settings.useTurbo,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            settings.copyWith(useTurbo: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.bool,
    );

    ArDriveDevToolOption defaultTurboUrlOption = ArDriveDevToolOption(
      name: 'defaultTurboUrl',
      value: settings.defaultTurboUrl,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            settings.copyWith(defaultTurboUrl: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.text,
    );

    ArDriveDevToolOption allowedDataItemSizeForTurboOption =
        ArDriveDevToolOption(
      name: 'allowedDataItemSizeForTurbo',
      value: settings.allowedDataItemSizeForTurbo,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            settings.copyWith(allowedDataItemSizeForTurbo: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.number,
    );

    ArDriveDevToolOption enableQuickSyncAuthoringOption = ArDriveDevToolOption(
      name: 'enableQuickSyncAuthoring',
      value: settings.enableQuickSyncAuthoring,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            settings.copyWith(enableQuickSyncAuthoring: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.bool,
    );

    ArDriveDevToolOption enableMultipleFileDownloadOption =
        ArDriveDevToolOption(
      name: 'enableMultipleFileDownload',
      value: settings.enableMultipleFileDownload,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            settings.copyWith(enableMultipleFileDownload: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.bool,
    );

    ArDriveDevToolOption enableVideoPreviewOption = ArDriveDevToolOption(
      name: 'enableVideoPreview',
      value: settings.enableVideoPreview,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            settings.copyWith(enableVideoPreview: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.bool,
    );

    ArDriveDevToolOption autoSyncIntervalInSecondsOption = ArDriveDevToolOption(
      name: 'autoSyncIntervalInSeconds',
      value: settings.autoSyncIntervalInSeconds,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            settings.copyWith(autoSyncIntervalInSeconds: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.number,
    );

    // reload option
    ArDriveDevToolOption reloadOption = ArDriveDevToolOption(
      name: 'Reload',
      value: '',
      onChange: (value) {
        html.window.location.reload();
      },
      type: ArDriveDevToolOptionType.button,
    );

    ArDriveDevToolOption resetOptions = ArDriveDevToolOption(
      name: 'Reset options',
      value: '',
      onChange: (value) async {
        await context.read<ConfigService>().resetDevToolsPrefs();

        _windowTitle.value = 'Reloading...';

        Future.delayed(const Duration(seconds: 1), () {
          html.window.location.reload();
        });
      },
      type: ArDriveDevToolOptionType.buttonTertiary,
    );

    ArDriveDevToolOption enableSyncFromSnapshotOption = ArDriveDevToolOption(
      name: 'enableSyncFromSnapshot',
      value: settings.enableSyncFromSnapshot,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            settings.copyWith(enableSyncFromSnapshot: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.bool,
    );

    List options = [
      defaultArweaveGatewayUrlOption,
      useTurboOption,
      defaultTurboUrlOption,
      allowedDataItemSizeForTurboOption,
      enableQuickSyncAuthoringOption,
      enableMultipleFileDownloadOption,
      enableVideoPreviewOption,
      autoSyncIntervalInSecondsOption,
      enableSyncFromSnapshotOption,
      reloadOption,
      resetOptions,
    ];

    return DraggableWindow(
      windowTitle: _windowTitle,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        itemBuilder: (context, index) => buildOption(options[index]),
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemCount: options.length,
      ),
    );
  }

  Widget buildOption(ArDriveDevToolOption option) {
    switch (option.type) {
      case ArDriveDevToolOptionType.text:
        return ArDriveTextField(
          label: option.name,
          initialValue: option.value,
          onFieldSubmitted: (value) {
            option.onChange(value);
            showOptionSavedMessage();
          },
        );
      case ArDriveDevToolOptionType.bool:
        return ArDriveToggleSwitch(
          text: option.name,
          value: option.value,
          onChanged: (value) {
            option.onChange(value);
            showOptionSavedMessage();
          },
        );
      case ArDriveDevToolOptionType.number:
        return ArDriveTextField(
          label: option.name,
          initialValue: option.value.toString(),
          onFieldSubmitted: (value) {
            option.onChange(int.tryParse(value) ?? 0);
            showOptionSavedMessage();
          },
          keyboardType: TextInputType.number,
        );

      case ArDriveDevToolOptionType.button:
        return ArDriveButton(
          text: option.name,
          onPressed: () => option.onChange(option.value),
        );
      case ArDriveDevToolOptionType.buttonTertiary:
        return ArDriveButton(
          style: ArDriveButtonStyle.tertiary,
          text: option.name,
          onPressed: () => option.onChange(option.value),
        );
    }
  }

  showOptionSavedMessage() {
    _windowTitle.value = 'Option saved!';

    Future.delayed(const Duration(seconds: 2), () {
      _windowTitle.value = 'ArDrive Dev Tools';
    });
  }
}

class DraggableWindow extends HookWidget {
  const DraggableWindow(
      {super.key,
      required this.child,
      required ValueNotifier<String> windowTitle})
      : _windowTitle = windowTitle;

  final Widget child;
  final ValueNotifier<String> _windowTitle;

  @override
  Widget build(BuildContext context) {
    final windowSize = useState<Size>(const Size(400, 800));
    final windowPos = useState<Offset>(Offset.zero);
    final isWindowVisible = useState<bool>(true);

    if (!isWindowVisible.value) {
      return Container();
    }

    return Positioned(
      top: windowPos.value.dy,
      left: windowPos.value.dx,
      child: Material(
        borderRadius: BorderRadius.circular(10),
        child: GestureDetector(
          onPanUpdate: (details) {
            windowPos.value += details.delta;
          },
          child: ArDriveCard(
            contentPadding: EdgeInsets.zero,
            boxShadow: BoxShadowCard.shadow100,
            width: windowSize.value.width,
            height: windowSize.value.height,
            content: Stack(
              children: [
                Padding(
                    padding: const EdgeInsets.only(top: 32.0), child: child),
                Container(
                  height: 32,
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: ValueListenableBuilder(
                          valueListenable: _windowTitle,
                          builder: (context, value, child) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child: Text(
                              value,
                              key: ValueKey<String>(value),
                              style: ArDriveTypography.body.bodyRegular(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeBgCanvas,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: ArDriveIconButton(
                          icon: ArDriveIcons.closeCircle(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeBgCanvas,
                          ),
                          onPressed: () {
                            isWindowVisible.value = false;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 8),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        windowSize.value += details.delta;
                      },
                      child: Icon(
                        Icons.open_with,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum ArDriveDevToolOptionType { text, bool, number, button, buttonTertiary }

typedef OnChange = void Function(dynamic value);

class ArDriveDevToolOption {
  final String name;
  dynamic value;
  final OnChange onChange;
  final ArDriveDevToolOptionType type;

  ArDriveDevToolOption({
    required this.name,
    required this.value,
    required this.onChange,
    required this.type,
  });
}
