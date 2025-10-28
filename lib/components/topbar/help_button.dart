import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_urls.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';

class HelpButtonTopBar extends StatelessWidget {
  const HelpButtonTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return HoverWidget(
      tooltip: appLocalizationsOf(context).help,
      child: ArDriveClickArea(
        child: GestureDetector(
          onTap: () {
            openHelp(context);
          },
          child: ArDriveIcons.question(color: colorTokens.textMid),
        ),
      ),
    );
  }
}
