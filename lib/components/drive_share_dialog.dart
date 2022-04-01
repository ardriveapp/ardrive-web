import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../utils/app_localizations_wrapper.dart';
import 'components.dart';

Future<void> promptToShareDrive({
  required BuildContext context,
  required Drive drive,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (_) => DriveShareCubit(
          drive: drive,
          driveDao: context.read<DriveDao>(),
          profileCubit: context.read<ProfileCubit>(),
        ),
        child: DriveShareDialog(),
      ),
    );

/// Depends on a provided [DriveShareCubit] for business logic.
class DriveShareDialog extends StatefulWidget {
  @override
  _DriveShareDialogState createState() => _DriveShareDialogState();
}

class _DriveShareDialogState extends State<DriveShareDialog> {
  final shareLinkController = TextEditingController();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DriveShareCubit, DriveShareState>(
        builder: (context, state) => AppDialog(
          title: appLocalizationsOf(context).shareDriveWithOthers,
          content: SizedBox(
            width: kLargeDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state is DriveShareLoadInProgress)
                  const Center(child: CircularProgressIndicator())
                else if (state is DriveShareLoadSuccess) ...{
                  ListTile(
                    title: Text(state.drive.name),
                    contentPadding: EdgeInsets.zero,
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: shareLinkController
                            ..text = state.driveShareLink.toString(),
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16)),
                        onPressed: () {
                          // Select the entire link to give the user some feedback on their action.
                          shareLinkController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: shareLinkController.text.length,
                          );

                          Clipboard.setData(
                              ClipboardData(text: shareLinkController.text));
                        },
                        child: Text(appLocalizationsOf(context).copyLink),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.drive.isPublic
                        ? appLocalizationsOf(context)
                            .anyoneCanAccessThisDrivePublic
                        : appLocalizationsOf(context)
                            .anyoneCanAccessThisDrivePrivate,
                    style: Theme.of(context).textTheme.subtitle2,
                  ),
                } else if (state is DriveShareLoadFail)
                  Text(state.message)
              ],
            ),
          ),
          actions: [
            if (state is DriveShareLoadSuccess)
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(appLocalizationsOf(context).doneEmphasized),
              ),
          ],
        ),
      );
}
