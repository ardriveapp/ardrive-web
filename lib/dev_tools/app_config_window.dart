import 'package:ardrive/main.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class AppConfigWindowManager extends StatefulWidget {
  const AppConfigWindowManager({super.key});

  @override
  State<AppConfigWindowManager> createState() => AppConfigWindowManagerState();
}

class AppConfigWindowManagerState extends State<AppConfigWindowManager> {
  final _focusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    return DraggableWindow(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArDriveToggleSwitch(
          value: context
                  .watch<ConfigService>()
                  .config
                  ?.enableMultipleFileDownload ??
              false,
          text: 'Enable Multi download',
          onChanged: ((value) {
            logger.d('Enable Multi download: $value');
            context.read<ConfigService>().updateAppConfig(
                config.copyWith(enableMultipleFileDownload: value));
          }),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Sync Time in seconds: ',
                style: ArDriveTypography.body.inputLargeBold()),
            const SizedBox(width: 8),
            Expanded(
              child: ArDriveTextField(
                hintText: 'Set Sync Time',
                onFieldSubmitted: (value) {
                  logger.d('Set Sync Time: $value');
                  context.read<ConfigService>().updateAppConfig(
                        config.copyWith(
                            syncTimerDurationInSeconds: int.parse(value)),
                      );
                  _focusNode.unfocus();
                },
                focusNode: _focusNode,
              ),
            ),
          ],
        )
      ],
    ));
  }
}

class DraggableWindow extends HookWidget {
  const DraggableWindow({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final windowSize = useState<Size>(const Size(400, 400));
    final windowPos = useState<Offset>(Offset.zero);
    final isWindowVisible = useState<bool>(true);

    logger.d('Window size: ${windowSize.value}');

    if (!isWindowVisible.value) {
      return Container();
    } // Don't render the window if not visible

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
                  padding:
                      const EdgeInsets.only(top: 40.0, left: 8.0, right: 8),
                  child: child,
                ),
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
                        child: Text('ArDrive Dev Tools',
                            style: ArDriveTypography.body.buttonNormalRegular(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeBgCanvas,
                            )),
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
