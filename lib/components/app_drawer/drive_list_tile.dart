import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';

import '../../../utils/app_localizations_wrapper.dart';

class DriveListTile extends StatelessWidget {
  final Drive drive;
  final bool selected;
  final VoidCallback onPressed;
  final bool hasAlert;

  const DriveListTile({
    required this.drive,
    required this.onPressed,
    this.selected = false,
    this.hasAlert = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListTile(
          minLeadingWidth: 12,
          leading: hasAlert
              ? Tooltip(
                  message: appLocalizationsOf(context).driveIssuesDetected,
                  child: const Icon(
                    Icons.info,
                    color: Color(kPrimaryValue),
                    size: 12,
                  ),
                )
              : null,
          trailing: drive.isPrivate
              ? const Icon(
                  Icons.lock_outline,
                  size: 12,
                )
              : null,
          title: Text(
            drive.name,
            style: TextStyle(fontSize: 12),
          ),
          selected: selected,
          onTap: onPressed,
        ),
      );
}
