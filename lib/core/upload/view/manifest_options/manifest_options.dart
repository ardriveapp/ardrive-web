import 'package:ardrive/core/upload/view/blocs/upload_manifest_options_bloc.dart';
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

          return Padding(
            padding: const EdgeInsets.only(bottom: 42.0),
            child: ListView.separated(
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              physics: scrollable
                  ? const ScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: manifestFiles.length,
              itemBuilder: (context, index) {
                final file = manifestFiles.elementAt(index).manifest;
                final isSelected = selectedManifestIds.contains(file.id);

                return _ManifestOptionTile(
                  manifestSelection: manifestFiles.elementAt(index),
                  isSelected: isSelected,
                  onSelect: () {
                    if (isSelected) {
                      context
                          .read<UploadManifestOptionsBloc>()
                          .add(DeselectManifest(manifest: file));
                    } else {
                      context
                          .read<UploadManifestOptionsBloc>()
                          .add(SelectManifest(manifest: file));
                    }
                  },
                );
              },
            ),
          );
        }

        return const SizedBox();
      },
    );
  }
}

class _ManifestOptionTile extends StatefulWidget {
  final ManifestSelection manifestSelection;
  final bool isSelected;
  final VoidCallback onSelect;

  const _ManifestOptionTile({
    required this.manifestSelection,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  State<_ManifestOptionTile> createState() => __ManifestOptionTileState();
}

class __ManifestOptionTileState extends State<_ManifestOptionTile> {
  @override
  Widget build(BuildContext context) {
    final state = context.read<UploadManifestOptionsBloc>().state;

    if (state is UploadManifestOptionsReady) {
      final file = widget.manifestSelection.manifest;

      final typography = ArDriveTypographyNew.of(context);
      final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
      final hiddenColor = colorTokens.textXLow;

      return SingleChildScrollView(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: colorTokens.containerL2,
            borderRadius: BorderRadius.circular(5),
          ),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          height: 50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  ArDriveCheckBox(
                    key: ValueKey(widget.isSelected),
                    checked: widget.isSelected,
                    onChange: (value) {
                      if (value) {
                        context
                            .read<UploadManifestOptionsBloc>()
                            .add(SelectManifest(manifest: file));
                      } else {
                        context
                            .read<UploadManifestOptionsBloc>()
                            .add(DeselectManifest(manifest: file));
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        ArDriveIcons.manifest(
                            size: 16,
                            color: file.isHidden ? hiddenColor : null),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            file.name,
                            style: typography.paragraphNormal(
                              color: file.isHidden ? hiddenColor : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (file.isHidden) ...[
                          const SizedBox(width: 8),
                          Text('(hidden)',
                              style: typography.paragraphNormal(
                                color: hiddenColor,
                              ))
                        ]
                      ],
                    ),
                  ),
                  const SizedBox.shrink()
                ],
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox();
  }
}
