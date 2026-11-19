import 'package:ardrive/core/upload/view/blocs/upload_manifest_options_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ManifestOptions extends StatelessWidget {
  const ManifestOptions({super.key, this.scrollable = true});

  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UploadManifestOptionsBloc, UploadManifestOptionsState>(
      builder: (context, state) {
        if (state is UploadManifestOptionsReady) {
          final selectedManifestIds = state.selectedManifestIds;
          final manifestFiles = state.manifestFiles;

          return ListView.builder(
            physics: scrollable
                ? const ScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: manifestFiles.length,
            itemBuilder: (context, index) {
              final file = manifestFiles.elementAt(index).manifest;
              return _ManifestOptionTile(
                manifestSelection: manifestFiles.elementAt(index),
                isSelected: selectedManifestIds.contains(file.id),
              );
            },
          );
        }

        return const SizedBox();
      },
    );
  }
}

/// One deployment that can take these files: a checkbox row like the other
/// options, its name after the deployment icon.
class _ManifestOptionTile extends StatelessWidget {
  final ManifestSelection manifestSelection;
  final bool isSelected;

  const _ManifestOptionTile({
    required this.manifestSelection,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final file = manifestSelection.manifest;
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final color = file.isHidden ? colorTokens.textLow : colorTokens.textHigh;

    void toggle(bool select) => context.read<UploadManifestOptionsBloc>().add(
          select
              ? SelectManifest(manifest: file)
              : DeselectManifest(manifest: file),
        );

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          ArDriveCheckBox(
            checked: isSelected,
            useNewIcons: true,
            onChange: toggle,
          ),
          const SizedBox(width: ArDriveSpacing.xs),
          ArDriveIcons.manifest(size: 16, color: color),
          const SizedBox(width: ArDriveSpacing.xs),
          Flexible(
            child: Text(
              file.name,
              style: typography.paragraphNormal(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (file.isHidden) ...[
            const SizedBox(width: ArDriveSpacing.xs),
            ArDriveTag(text: appLocalizationsOf(context).itemHiddenTag),
          ],
        ],
      ),
    );
  }
}
