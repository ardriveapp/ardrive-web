import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/selected_item.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/blocs.dart';
import '../models/daos/drive_dao/drive_dao.dart';
import '../services/arweave/arweave_service.dart';

class DetailsPanel extends StatefulWidget {
  const DetailsPanel({
    super.key,
    required this.item,
    required this.maybeSelectedItem,
  });

  final ArDriveDataTableItem item;
  final SelectedItem? maybeSelectedItem;
  @override
  State<DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<DetailsPanel> {
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      // Specify a key to ensure a new cubit is provided when the folder/file id changes.
      key: widget.maybeSelectedItem?.id != null
          ? ValueKey(
              '${widget.item.driveId}${widget.maybeSelectedItem?.id}',
            )
          : UniqueKey(),
      providers: [
        BlocProvider<FsEntryInfoCubit>(
          create: (context) => FsEntryInfoCubit(
            driveId: widget.item.driveId,
            maybeSelectedItem: widget.maybeSelectedItem,
            driveDao: context.read<DriveDao>(),
          ),
        ),
        BlocProvider<FsEntryPreviewCubit>(
          create: (context) => FsEntryPreviewCubit(
            crypto: ArDriveCrypto(),
            driveId: widget.item.driveId,
            maybeSelectedItem: widget.maybeSelectedItem,
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            arweave: context.read<ArweaveService>(),
            config: context.read<AppConfig>(),
          ),
        )
      ],
      child: BlocBuilder<FsEntryPreviewCubit, FsEntryPreviewState>(
          builder: (context, previewState) {
        final tabs = [
          if (previewState is FsEntryPreviewSuccess)
            ArDriveTab(
                Tab(
                  child: Text(
                    appLocalizationsOf(context).itemPreviewEmphasized,
                  ),
                ),
                _buildPreview(previewState)),
          ArDriveTab(
            Tab(
              child: Text(
                appLocalizationsOf(context).itemDetailsEmphasized,
              ),
            ),
            _buildDetails(),
          ),
          ArDriveTab(
            Tab(
              child: Text(
                appLocalizationsOf(context).itemActivityEmphasized,
              ),
            ),
            _buildActivity(),
          )
        ];
        return SizedBox(
          child: ArDriveCard(
            backgroundColor:
                ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
            contentPadding: const EdgeInsets.all(24),
            content: Column(
              children: [
                ArDriveCard(
                  contentPadding: const EdgeInsets.all(24),
                  backgroundColor: ArDriveTheme.of(context)
                      .themeData
                      .tableTheme
                      .selectedItemColor,
                  content: Row(
                    children: [
                      DriveExplorerItemTileLeading(
                        item: widget.item,
                      ),
                      Flexible(
                        child: Text(
                          widget.item.name,
                          style: ArDriveTypography.body.buttonLargeBold(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 48,
                ),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: ArDriveTabView(
                    key: Key(widget.item.id + tabs.length.toString()),
                    tabs: tabs,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPreview(previewState) {
    return Align(
      alignment: Alignment.center,
      child: FsEntryPreviewWidget(
        state: previewState,
      ),
    );
  }

  Widget _buildDetails() {
    return Container();
  }

  Widget _buildActivity() {
    return Container();
  }
}
