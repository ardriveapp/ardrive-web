import 'package:ardrive/services/license/license_types.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';

class LicenseDetailsPopoverButton extends StatefulWidget {
  final LicenseState licenseState;

  const LicenseDetailsPopoverButton({
    super.key,
    required this.licenseState,
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
      anchor: const Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
        offset: Offset(0, 4),
      ),
      content: LicenseDetailsPopover(licenseState: widget.licenseState),
      child: ArDriveButton(
        text: widget.licenseState.meta.shortName,
        style: ArDriveButtonStyle.tertiary,
        onPressed: () {
          setState(() {
            _showLicenseDetailsCard = !_showLicenseDetailsCard;
          });
        },
      ),
    );
  }
}

class LicenseDetailsPopover extends StatelessWidget {
  final LicenseState licenseState;

  const LicenseDetailsPopover({
    super.key,
    required this.licenseState,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveCard(
      content: Text(licenseState.meta.name),
    );
  }
}
