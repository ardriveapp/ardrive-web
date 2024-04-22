import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
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
    this.onClose,
    this.padding,
  });

  final Widget content;
  final double? width;
  final bool hasCloseButton;
  final Function()? onClose;
  final EdgeInsets? padding;

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

    final contentPadding = (deviceWidth < TABLET)
        ? EdgeInsets.fromLTRB(22, hasCloseButton ? 0 : 44, 22, 32)
        : EdgeInsets.fromLTRB(56, hasCloseButton ? 0 : 44, 56, 64);

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
              if (hasCloseButton)
                Padding(
                  padding: const EdgeInsets.all(22.0),
                  child: hasCloseButton
                      ? ArDriveClickArea(
                          child: GestureDetector(
                            onTap: onClose ?? () => Navigator.pop(context),
                            child: const Align(
                              alignment: Alignment.centerRight,
                              child: ArDriveIcon(
                                icon: ArDriveIconsData.x,
                                size: 20,
                              ),
                            ),
                          ),
                        )
                      : Container(),
                )
            ]),
            Padding(
              padding: padding ?? contentPadding,
              child: content,
            ),
          ],
        ),
      ),
    );
  }
}
