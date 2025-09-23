import 'dart:convert';

import 'package:ardrive/dev_tools/drives_health_check.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:universal_html/html.dart' as html;

/// The `ArDriveDevTools` class is responsible for managing the development tools in ArDrive.
/// This is a singleton class, meaning it ensures only a single instance can exist.
///
/// The dev tools are displayed through an `OverlayEntry`, and their state is tracked
/// by the `_isDevToolsOpen` boolean.
///
/// The `showDevTools` method is used to display the dev tools and the `closeDevTools`
/// method is used to close them. Both methods first check the state of the dev tools
/// before performing any action, and they log their actions for debugging purposes.
class ArDriveDevTools {
  // implement singleton
  static final ArDriveDevTools _instance = ArDriveDevTools._internal();

  factory ArDriveDevTools() => _instance;

  BuildContext? _context;

  // getter
  static ArDriveDevTools get instance => _instance;
  BuildContext? get context => _context;

  ArDriveDevTools._internal();

  final _devToolsWindow =
      OverlayEntry(builder: (context) => const AppConfigWindowManager());

  bool _isDevToolsOpen = false;

  void showDevTools({BuildContext? optionalContext}) {
    _context = optionalContext;

    if (_isDevToolsOpen) return;

    _isDevToolsOpen = true;

    logger.i('Opening dev tools');

    overlayKey.currentState?.insert(_devToolsWindow);
  }

  void closeDevTools() {
    if (!_isDevToolsOpen) return;

    logger.i('Closing dev tools');

    _devToolsWindow.remove();

    _isDevToolsOpen = false;
  }
}

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
    final ConfigService configService = context.read<ConfigService>();
    final AppConfig config = configService.config;

    const graphqlSuffix = '/graphql';

    final ArDriveDevToolOption defaultArweaveGatewayUrlOption =
        ArDriveDevToolOption(
      name: 'defaultArweaveGatewayUrl',
      value: config.defaultArweaveGatewayUrl,
      onChange: (value) {
        setState(() {
          final normalizedValue = value != null && value.endsWith(graphqlSuffix)
              ? value.substring(0, value.length - graphqlSuffix.length)
              : value;
          configService.updateAppConfig(
            config.copyWith(defaultArweaveGatewayUrl: normalizedValue),
          );
          if (normalizedValue != null && normalizedValue.isNotEmpty) {
            context
                .read<ArweaveService>()
                .updateGraphQLEndpoint(normalizedValue);
          }
        });
      },
      type: ArDriveDevToolOptionType.text,
    );

    final ArDriveDevToolOption useTurboOption = ArDriveDevToolOption(
      name: 'useTurboUpload',
      value: config.useTurboUpload,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            config.copyWith(useTurboUpload: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.bool,
    );

    final ArDriveDevToolOption useTurboPaymentOption = ArDriveDevToolOption(
      name: 'useTurboPayment',
      value: config.useTurboPayment,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            config.copyWith(useTurboPayment: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.bool,
    );

    final ArDriveDevToolOption defaultTurboUrlOption = ArDriveDevToolOption(
      name: 'defaultTurboUrl',
      value: config.defaultTurboUploadUrl,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            config.copyWith(defaultTurboUploadUrl: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.text,
    );

    final ArDriveDevToolOption stripePublishableKey = ArDriveDevToolOption(
      name: 'stripePublishableKey',
      value: config.stripePublishableKey,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            config.copyWith(stripePublishableKey: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.text,
    );

    final ArDriveDevToolOption allowedDataItemSizeForTurboOption =
        ArDriveDevToolOption(
      name: 'allowedDataItemSizeForTurbo',
      value: config.allowedDataItemSizeForTurbo,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            config.copyWith(allowedDataItemSizeForTurbo: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.number,
    );

    final ArDriveDevToolOption autoSyncIntervalInSecondsOption =
        ArDriveDevToolOption(
      name: 'autoSyncIntervalInSeconds',
      value: config.autoSyncIntervalInSeconds,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            config.copyWith(autoSyncIntervalInSeconds: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.number,
    );

    // reload option
    final ArDriveDevToolOption reloadOption = ArDriveDevToolOption(
      name: 'Reload',
      value: '',
      onChange: (value) {
        html.window.location.reload();
      },
      type: ArDriveDevToolOptionType.button,
    );

    final ArDriveDevToolOption runHealthCheck = ArDriveDevToolOption(
      name: 'Run Health Check',
      value: '',
      onChange: (value) {
        final BuildContext context = ArDriveDevTools().context!;

        showArDriveDialog(
          context,
          content: const DrivesHealthCheckModal(),
        );
      },
      type: ArDriveDevToolOptionType.button,
    );

    final ArDriveDevToolOption resetOptions = ArDriveDevToolOption(
      name: 'Reset options',
      value: '',
      onChange: (value) async {
        await context.read<ConfigService>().resetDevToolsPrefs();

        reloadPage();
      },
      type: ArDriveDevToolOptionType.buttonTertiary,
    );

    final ArDriveDevToolOption enableSyncFromSnapshotOption =
        ArDriveDevToolOption(
      name: 'enableSyncFromSnapshot',
      value: config.enableSyncFromSnapshot,
      onChange: (value) {
        setState(() {
          configService.updateAppConfig(
            config.copyWith(enableSyncFromSnapshot: value),
          );
        });
      },
      type: ArDriveDevToolOptionType.bool,
    );

    final List<ArDriveDevToolOption> options = [
      runHealthCheck,
      useTurboOption,
      useTurboPaymentOption,
      enableSyncFromSnapshotOption,
      stripePublishableKey,
      allowedDataItemSizeForTurboOption,
      defaultArweaveGatewayUrlOption,
      defaultTurboUrlOption,
      autoSyncIntervalInSecondsOption,
      reloadOption,
      resetOptions,
    ];

    final typography = ArDriveTypographyNew.of(context);

    return DraggableWindow(
      windowTitle: _windowTitle,
      child: SingleChildScrollView(
        primary: true,
        child: Column(
          children: [
            const SizedBox(height: 48),
            FutureBuilder(
                future: _readConfigsFromEnv(),
                builder: (context, snapshot) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Flexible(
                          child: ArDriveButtonNew(
                            text: 'dev env',
                            typography: typography,
                            variant: ButtonVariant.primary,
                            onPressed: () {
                              setState(() {
                                _windowTitle.value = 'Reloading...';

                                configService.updateAppConfig(
                                  AppConfig.fromJson(snapshot.data![0]),
                                );
                              });

                              Future.delayed(const Duration(seconds: 1), () {
                                setState(() {
                                  _windowTitle.value = 'Dev config';
                                  reloadPage();
                                });
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          child: ArDriveButtonNew(
                            text: 'staging env',
                            variant: ButtonVariant.primary,
                            typography: typography,
                            onPressed: () {
                              setState(() {
                                _windowTitle.value = 'Reloading...';

                                configService.updateAppConfig(
                                  AppConfig.fromJson(snapshot.data![2]),
                                );
                              });

                              Future.delayed(const Duration(seconds: 1), () {
                                setState(() {
                                  _windowTitle.value = 'Staging config';
                                  reloadPage();
                                });
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          child: ArDriveButtonNew(
                            text: 'prod env',
                            variant: ButtonVariant.primary,
                            typography: typography,
                            onPressed: () {
                              setState(() {
                                _windowTitle.value = 'Reloading...';

                                configService.updateAppConfig(
                                  AppConfig.fromJson(snapshot.data![1]),
                                );
                              });

                              Future.delayed(const Duration(seconds: 1), () {
                                setState(() {
                                  _windowTitle.value = 'Prod config';
                                });
                              });
                            },
                          ),
                        )
                      ],
                    ),
                  );
                }),
            ListView.separated(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) => buildOption(options[index]),
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemCount: options.length,
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _readConfigsFromEnv() async {
    final String devConfig =
        await rootBundle.loadString('assets/config/dev.json');
    final String prodConfig =
        await rootBundle.loadString('assets/config/prod.json');
    final String stagingConfig =
        await rootBundle.loadString('assets/config/staging.json');

    final List<Map<String, dynamic>> configs = [
      jsonDecode(devConfig),
      jsonDecode(prodConfig),
      jsonDecode(stagingConfig),
    ];

    return configs;
  }

  Widget buildOption(ArDriveDevToolOption option) {
    switch (option.type) {
      case ArDriveDevToolOptionType.text:
        return ArDriveTextFieldNew(
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
        return ArDriveTextFieldNew(
          label: option.name,
          initialValue: option.value.toString(),
          onFieldSubmitted: (value) {
            option.onChange(int.tryParse(value) ?? 0);
            showOptionSavedMessage();
          },
          keyboardType: TextInputType.number,
        );

      case ArDriveDevToolOptionType.button:
        return ArDriveButtonNew(
          variant: ButtonVariant.primary,
          typography: ArDriveTypographyNew.of(context),
          text: option.name,
          onPressed: () {
            option.onChange(option.value);
            option.onInteraction?.call();
          },
        );

      case ArDriveDevToolOptionType.buttonTertiary:
        return ArDriveButtonNew(
          variant: ButtonVariant.outline,
          typography: ArDriveTypographyNew.of(context),
          text: option.name,
          onPressed: () => option.onChange(option.value),
        );

      case ArDriveDevToolOptionType.turboCredits:
        final optionAsBigInt = option as ArDriveDevToolOption<BigInt?>;
        return ArDriveTextField(
          label: optionAsBigInt.name,
          initialValue: optionAsBigInt.value != null
              ? (optionAsBigInt.value! / BigInt.from(1000000000000)).toString()
              : '',
          onFieldSubmitted: (value) {
            final doubleVaue = double.tryParse(value);
            if (doubleVaue == null) {
              optionAsBigInt.onChange(null);
              showOptionSavedMessage();
              return;
            }

            final winstonCredits = BigInt.from(
              (doubleVaue * 1000000000000).floor(),
            );
            optionAsBigInt.onChange(winstonCredits);
            showOptionSavedMessage();
          },
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,12}')),
          ],
        );
    }
  }

  showOptionSavedMessage() {
    _windowTitle.value = 'Option saved!';

    Future.delayed(const Duration(seconds: 2), () {
      _windowTitle.value = 'ArDrive Dev Tools';
    });
  }

  void reloadPage() {
    _windowTitle.value = 'Reloading...';

    Future.delayed(const Duration(seconds: 1), () {
      html.window.location.reload();
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
    double height = 600;
    double width = 600;
    if (AppPlatform.isMobile) {
      width = MediaQuery.of(context).size.width * 0.95;
      height = MediaQuery.of(context).size.height * 0.8;
    }

    final windowSize = useState<Size>(Size(width, height));
    final windowPos = useState<Offset>(const Offset(5, 32));
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
            elevation: 5,
            contentPadding: EdgeInsets.zero,
            boxShadow: BoxShadowCard.shadow100,
            width: windowSize.value.width,
            height: windowSize.value.height,
            content: Stack(
              children: [
                Padding(
                    padding: const EdgeInsets.only(top: 32.0), child: child),
                Container(
                  height: 64,
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
                              style: ArDriveTypography.body.bodyBold(
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
                        child: Padding(
                          padding: const EdgeInsets.only(top: 20, right: 8),
                          child: ArDriveClickArea(
                            child: GestureDetector(
                              onTap: () {
                                ArDriveDevTools().closeDevTools();
                              },
                              child: ArDriveIcons.x(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colorTokens
                                    .iconLow,
                              ),
                            ),
                          ),
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

enum ArDriveDevToolOptionType {
  text,
  bool,
  number,
  button,
  buttonTertiary,
  turboCredits,
}

typedef OnChange<T> = void Function(T value);

class ArDriveDevToolOption<T> {
  final String name;
  T value;
  final OnChange<T> onChange;
  final ArDriveDevToolOptionType type;
  final Function? onInteraction;

  ArDriveDevToolOption({
    required this.name,
    required this.value,
    required this.onChange,
    required this.type,
    this.onInteraction,
  });
}
