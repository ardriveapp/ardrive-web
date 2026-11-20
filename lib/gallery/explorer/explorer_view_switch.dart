import 'package:ardrive/gallery/explorer/explorer_view_mode.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The List and Gallery switch in a folder's bar.
///
/// Two joined icon buttons on a wide screen (list, photo grid), as Google
/// Drive has them; on a phone, one icon button that switches to the other
/// view. Both are named "List" and "Gallery" for tooltips and screen readers.
class ExplorerViewSwitch extends StatelessWidget {
  const ExplorerViewSwitch({
    super.key,
    required this.mode,
    required this.onChanged,
    this.compact = false,
  });

  final ExplorerViewMode mode;
  final ValueChanged<ExplorerViewMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final list = mode == ExplorerViewMode.list;

    if (compact) {
      // Shows the view it switches to, labelled as that view.
      return ArDriveIconButton(
        key: const ValueKey('explorer-view-switch-compact'),
        tooltip: list ? l10n.explorerViewGallery : l10n.explorerViewList,
        icon: list ? ArDriveIcons.galleryGrid() : ArDriveIcons.listView(),
        onPressed: () => onChanged(
          list ? ExplorerViewMode.gallery : ExplorerViewMode.list,
        ),
      );
    }

    return ArDriveIconSegmentedControl<ExplorerViewMode>(
      key: const ValueKey('explorer-view-switch'),
      selected: mode,
      onSelected: onChanged,
      segments: [
        ArDriveIconSegment(
          value: ExplorerViewMode.list,
          icon: ArDriveIcons.listView().icon,
          label: l10n.explorerViewList,
        ),
        ArDriveIconSegment(
          value: ExplorerViewMode.gallery,
          icon: ArDriveIcons.galleryGrid().icon,
          label: l10n.explorerViewGallery,
        ),
      ],
    );
  }
}
