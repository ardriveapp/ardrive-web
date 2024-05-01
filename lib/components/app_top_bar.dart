import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/gift/reedem_button.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/search/search_modal.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final enableSearch = context.read<ConfigService>().config.enableSearch;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final controller = TextEditingController();

    return SizedBox(
      height: 110,
      width: double.maxFinite,
      child: Padding(
        padding: const EdgeInsets.only(right: 24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (enableSearch) ...[
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: SearchTextField(
                    controller: controller,
                    onFieldSubmitted: (query) {
                      showArDriveDialog(
                        context,
                        content: FileSearchModal(
                          initialQuery: query,
                          driveDetailCubit: context.read<DriveDetailCubit>(),
                          onSearch: (query) {
                            controller.text = query;
                          },
                        ),
                        barrierColor: colorTokens.containerL1.withOpacity(0.8),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 24),
            ],
            const Spacer(),
            const SyncButton(),
            const SizedBox(width: 24),
            const RedeemButton(),
            const SizedBox(width: 24),
            const ProfileCard(),
          ],
        ),
      ),
    );
  }
}

class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return HoverWidget(
      tooltip: appLocalizationsOf(context).resyncTooltip,
      child: ArDriveDropdown(
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
        ),
        items: [
          ArDriveDropdownItem(
            onClick: () {
              context.read<SyncCubit>().startSync(deepSync: false);
              PlausibleEventTracker.trackResync(type: ResyncType.resync);
            },
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).resync,
              icon: ArDriveIcons.refresh(
                color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              ),
            ),
          ),
          ArDriveDropdownItem(
            onClick: () {
              context.read<SyncCubit>().startSync(deepSync: true);
              PlausibleEventTracker.trackResync(type: ResyncType.deepResync);
            },
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).deepResync,
              icon: ArDriveIcons.cloudSync(
                color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              ),
            ),
          ),
        ],
        child: ArDriveIcons.refresh(
          color: colorTokens.textMid,
        ),
      ),
    );
  }
}
