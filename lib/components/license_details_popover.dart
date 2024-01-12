import 'package:ardrive/components/fs_entry_license_form.dart';
import 'package:ardrive/components/license_summary.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';

class LicenseDetailsPopoverButton extends StatefulWidget {
  final LicenseState licenseState;
  final FileDataTableItem fileItem;
  final Aligned anchor;

  const LicenseDetailsPopoverButton({
    super.key,
    required this.licenseState,
    required this.fileItem,
    required this.anchor,
  });

  @override
  State<LicenseDetailsPopoverButton> createState() =>
      _LicenseDetailsPopoverButtonState();
}

class _LicenseDetailsPopoverButtonState
    extends State<LicenseDetailsPopoverButton> {
  bool _showLicenseDetailsCard = false;

  @override
  Widget build(BuildContext context) {
    return ArDriveOverlay(
      onVisibleChange: (visible) {
        if (!visible) {
          setState(() {
            _showLicenseDetailsCard = false;
          });
        }
      },
      visible: _showLicenseDetailsCard,
      anchor: widget.anchor,
      content: LicenseDetailsPopover(
        licenseState: widget.licenseState,
        fileItem: widget.fileItem,
        closePopover: () {
          setState(() {
            _showLicenseDetailsCard = false;
          });
        },
      ),
      child: HoverWidget(
        hoverScale: 1.0,
        tooltip:
            // TODO: Localize
            // appLocalizations.of(context).licenseDetails,
            'View license details',
        child: ArDriveButton(
          text: widget.licenseState.meta.shortName,
          style: ArDriveButtonStyle.tertiary,
          onPressed: () {
            setState(() {
              _showLicenseDetailsCard = !_showLicenseDetailsCard;
            });
          },
        ),
      ),
    );
  }
}

class LicenseDetailsPopover extends StatelessWidget {
  final LicenseState licenseState;
  final FileDataTableItem fileItem;
  final VoidCallback closePopover;

  const LicenseDetailsPopover({
    super.key,
    required this.licenseState,
    required this.fileItem,
    required this.closePopover,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveCard(
      contentPadding: const EdgeInsets.all(16),
      boxShadow: BoxShadowCard.shadow80,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LicenseSummary(licenseState: licenseState),
          ArDriveButton(
            text:
                // TODO: Localize
                // appLocalizationsOf(context).licenseUpdate
                'Update',
            icon: ArDriveIcons.license(
              size: 16,
              color: ArDriveTheme.of(context).themeData.backgroundColor,
            ),
            fontStyle: ArDriveTypography.body.buttonNormalBold(
              color: ArDriveTheme.of(context).themeData.backgroundColor,
            ),
            backgroundColor:
                ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            maxHeight: 32,
            onPressed: () {
              closePopover();
              promptToLicense(
                context,
                driveId: fileItem.driveId,
                selectedItems: [fileItem],
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
