import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url_utils.dart';
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
      child: ArDriveDropdown(
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
        ),
        items: [
          ArDriveDropdownItem(
            onClick: () {
              openDocs();
            },
            content: const ArDriveDropdownItemTile(
              name: 'Docs',
            ),
          ),
          ArDriveDropdownItem(
            onClick: () {
              openHelp();
            },
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).help,
            ),
          ),
          ArDriveDropdownItem(
            onClick: () {
              openFeedbackSurveyUrl();
            },
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).leaveFeedback,
            ),
          ),
          ArDriveDropdownItem(
            onClick: () {
              shareLogs(context: context);
            },
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).shareLogsText,
            ),
          ),
        ],
        child: ArDriveIcons.question(color: colorTokens.textMid),
      ),
    );
  }
}
