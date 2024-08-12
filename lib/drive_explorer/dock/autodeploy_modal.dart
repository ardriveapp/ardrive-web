import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/drive_explorer/dock/ardrive_dock.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AutoDeployWidget extends StatefulWidget {
  const AutoDeployWidget({super.key, required this.createManifestCubit});

  final CreateManifestCubit createManifestCubit;

  @override
  State<AutoDeployWidget> createState() => _AutoDeployWidgetState();
}

class _AutoDeployWidgetState extends State<AutoDeployWidget> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder(
      bloc: widget.createManifestCubit,
      builder: (context, state) {
        final typography = ArDriveTypographyNew.of(context);

        if (state is CreateManifestUploadInProgress) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Updating manifest with the new assets...',
                style: typography.paragraphLarge(fontWeight: ArFontWeight.bold),
              ),
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          );
        }

        if (state is CreateManifestSuccess) {
          Future.delayed(const Duration(seconds: 3), () {
            ArDriveDock.of(context).removeOverlay();
          });

          return Text('AutoDeploy: Upload success!',
              style: typography.paragraphLarge(fontWeight: ArFontWeight.bold));
        }

        return Text(
          'AutoDeploy: Uploading manifest...',
          style: typography.paragraphLarge(fontWeight: ArFontWeight.bold),
        );
      },
    );
  }
}
