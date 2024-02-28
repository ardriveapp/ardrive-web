import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

// FIXME: Taken from ardrive_ui, work out moving this there when design is complete
const double modalStandardMaxWidthSize = 350;

class ArDriveLoginModal extends StatelessWidget {
  const ArDriveLoginModal({
    super.key,
    required this.content,
    this.width,
    this.hasCloseButton = true,
  });

  final Widget content;
  final double? width;
  final bool hasCloseButton;

  @override
  Widget build(BuildContext context) {
    late double maxWidth;
    final deviceWidth = MediaQuery.of(context).size.width;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    if (deviceWidth < modalStandardMaxWidthSize) {
      maxWidth = deviceWidth;
    } else {
      maxWidth = modalStandardMaxWidthSize;
    }

    return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: 100,
          maxWidth: width ?? maxWidth,
          minWidth: 250,
        ),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: colorTokens.containerL3,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  height: 6,
                  child: Container(
                    color: colorTokens.containerRed,
                  )),
              Row(children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(22.0),
                  child: ArDriveClickArea(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Align(
                        alignment: Alignment.centerRight,
                        child: ArDriveIcon(
                          icon: ArDriveIconsData.x,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                )
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 56, 64),
                child: content,
              ),
            ],
          ),
        ));
  }
}
