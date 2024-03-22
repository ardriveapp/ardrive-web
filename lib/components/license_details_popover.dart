import 'package:ardrive/components/license_summary.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';

class LicenseDetailsPopover extends StatelessWidget {
  final LicenseState licenseState;
  final VoidCallback closePopover;

  final bool showLicenseName;
  final Widget? child;

  const LicenseDetailsPopover({
    super.key,
    required this.licenseState,
    required this.closePopover,
    this.showLicenseName = true,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveCard(
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      boxShadow: BoxShadowCard.shadow80,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LicenseSummary(
            licenseState: licenseState,
            showLicenseName: showLicenseName,
          ),
          if (child != null) ...[
            const SizedBox(height: 8),
            child!,
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }
}
