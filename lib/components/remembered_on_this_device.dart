import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/components/details_panel.dart' show DetailsPanelItem;
import 'package:ardrive/device_unlock/data/device_tabs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Whether this device remembers a private drive's key, and the way to make
/// it forget: "Forget on this device". The drive stays open for the session
/// (its key moves to memory) and is locked the next time.
class RememberedOnThisDevice extends StatelessWidget {
  const RememberedOnThisDevice({super.key, required this.driveId});

  final String driveId;

  @override
  Widget build(BuildContext context) {
    final driveDao = context.read<DriveDao>();
    final typography = ArDriveTypographyNew.of(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final strings = appLocalizationsOf(context);

    return StreamBuilder<bool>(
      stream: driveDao.watchDriveKeyRemembered(driveId),
      builder: (context, snapshot) {
        final remembered = snapshot.data;
        if (remembered == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DetailsPanelItem(
              itemTitle: strings.onThisDevice,
              leading: Text(
                remembered
                    ? strings.rememberedOnThisDevice
                    : strings.notRememberedOnThisDevice,
                key: Key(remembered
                    ? 'driveRememberedOnThisDevice'
                    : 'driveNotRememberedOnThisDevice'),
                style: typography.paragraphNormal(color: colors.textMid),
                textAlign: TextAlign.right,
              ),
            ),
            if (remembered) ...[
              const SizedBox(height: 12),
              ArDriveButtonNew(
                key: const Key('forgetDriveOnThisDevice'),
                text: strings.forgetOnThisDevice,
                typography: typography,
                variant: ButtonVariant.secondary,
                size: ArDriveButtonSize.compact,
                onPressed: () async {
                  final user = context.read<ArDriveAuth>().currentUser;
                  if (await driveDao.forgetDriveKey(driveId, user.cipherKey)) {
                    DeviceTabs.instance.announceForgotten([driveId]);
                  }
                },
              ),
            ],
          ],
        );
      },
    );
  }
}
