import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/license/licenses/udl.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../pages/drive_detail/drive_detail_page.dart';
import 'components.dart';

Future<void> promptToLicense(
  BuildContext context, {
  required String driveId,
  required List<ArDriveDataTableItem> selectedItems,
}) {
  return showArDriveDialog(
    context,
    content: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => FsEntryLicenseBloc(
            driveId: driveId,
            selectedItems: selectedItems,
            arweave: context.read<ArweaveService>(),
            turboUploadService: context.read<TurboUploadService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            licenseService: context.read<LicenseService>(),
          ),
        ),
        BlocProvider.value(
          value: context.read<DriveDetailCubit>(),
        )
      ],
      child: FsEntryLicenseForm(
        selectedItems: selectedItems,
      ),
    ),
  );
}

class FsEntryLicenseForm extends StatelessWidget {
  final List<ArDriveDataTableItem> selectedItems;

  const FsEntryLicenseForm({
    Key? key,
    required this.selectedItems,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FsEntryLicenseBloc, FsEntryLicenseState>(
      listener: (context, state) {
        if (state is FsEntryLicenseLoadInProgress) {
          showProgressDialog(
            context,
            title: 'licensingItemsEmphasized',
            // TODO: Localize
            // title: appLocalizationsOf(context).licensingItemsEmphasized,
          );
        } else if (state is FsEntryLicenseSuccess) {
          Navigator.pop(context);
          Navigator.pop(context);
        } else if (state is FsEntryLicenseWalletMismatch) {
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        return Builder(builder: (context) {
          if (state is FsEntryLicenseSelecting) {
            final items = [
              ...selectedItems.map(
                (f) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16.0, horizontal: 16),
                    child: GestureDetector(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ArDriveIcons.folderOutline(
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f.name,
                              style:
                                  ArDriveTypography.body.inputNormalRegular(),
                            ),
                          ),
                          ArDriveIcons.carretRight(
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              ...selectedItems.map(
                (f) => Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16.0,
                    horizontal: 16,
                  ),
                  child: Row(
                    children: [
                      ArDriveIcons.fileOutlined(
                        size: 16,
                        color: _colorDisabled(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f.name,
                          style: ArDriveTypography.body.inputNormalRegular(
                            color: _colorDisabled(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ];

            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: ArDriveCard(
                height: 441,
                width: kMediumDialogWidth,
                contentPadding: EdgeInsets.zero,
                content: SizedBox(
                  height: 325,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.only(left: 16, right: 16),
                        width: double.infinity,
                        height: 77,
                        alignment: Alignment.centerLeft,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeBgCanvas,
                        child: Row(
                          children: [
                            AnimatedContainer(
                              width: 0,
                              duration: const Duration(milliseconds: 200),
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 200),
                                scale: 0,
                                child: ArDriveIcons.arrowLeft(
                                  size: 32,
                                ),
                              ),
                            ),
                            AnimatedPadding(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.only(left: 0),
                              child: Text(
                                'licenseItems',
                                // TODO: Localize
                                // appLocalizationsOf(context).licenseItems,
                                style:
                                    ArDriveTypography.headline.headline5Bold(),
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                              },
                              child: ArDriveIcons.x(
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            return items[index];
                          },
                        ),
                      ),
                      const Divider(),
                      Container(
                        decoration: BoxDecoration(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeBgSurface,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ArDriveButton(
                              maxHeight: 36,
                              backgroundColor: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                              fontStyle:
                                  ArDriveTypography.body.buttonNormalRegular(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeAccentSubtle,
                              ),
                              text: 'licenseHereEmphasized',
                              // TODO: Localize
                              // text: appLocalizationsOf(context)
                              // .licenseHereEmphasized,
                              onPressed: () {
                                context.read<FsEntryLicenseBloc>().add(
                                      const FsEntryLicenseSelect(
                                        licenseInfo: udlLicenseInfo,
                                      ),
                                    );
                                context
                                    .read<DriveDetailCubit>()
                                    .forceDisableMultiselect = true;
                              },
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            );
          } else if (state is FsEntryLicenseConfiguring) {
            final items = [
              ...selectedItems.map(
                (f) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16.0, horizontal: 16),
                    child: GestureDetector(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ArDriveIcons.folderOutline(
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f.name,
                              style:
                                  ArDriveTypography.body.inputNormalRegular(),
                            ),
                          ),
                          ArDriveIcons.carretRight(
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              ...selectedItems.map(
                (f) => Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16.0,
                    horizontal: 16,
                  ),
                  child: Row(
                    children: [
                      ArDriveIcons.fileOutlined(
                        size: 16,
                        color: _colorDisabled(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f.name,
                          style: ArDriveTypography.body.inputNormalRegular(
                            color: _colorDisabled(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ];

            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: ArDriveCard(
                height: 441,
                width: kMediumDialogWidth,
                contentPadding: EdgeInsets.zero,
                content: SizedBox(
                  height: 325,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.only(left: 16, right: 16),
                        width: double.infinity,
                        height: 77,
                        alignment: Alignment.centerLeft,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeBgCanvas,
                        child: Row(
                          children: [
                            AnimatedContainer(
                              width: 0,
                              duration: const Duration(milliseconds: 200),
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 200),
                                scale: 0,
                                child: ArDriveIcons.arrowLeft(
                                  size: 32,
                                ),
                              ),
                            ),
                            AnimatedPadding(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.only(left: 0),
                              child: Text(
                                'licenseItems',
                                // TODO: Localize
                                // appLocalizationsOf(context).licenseItems,
                                style:
                                    ArDriveTypography.headline.headline5Bold(),
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                              },
                              child: ArDriveIcons.x(
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            return items[index];
                          },
                        ),
                      ),
                      const Divider(),
                      Container(
                        decoration: BoxDecoration(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeBgSurface,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ArDriveButton(
                              maxHeight: 36,
                              backgroundColor: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                              fontStyle:
                                  ArDriveTypography.body.buttonNormalRegular(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeAccentSubtle,
                              ),
                              text: 'licenseHereEmphasized',
                              // TODO: Localize
                              // text: appLocalizationsOf(context)
                              // .licenseHereEmphasized,
                              onPressed: () {
                                context.read<FsEntryLicenseBloc>().add(
                                      FsEntryLicenseSubmit(
                                        licenseInfo: state.licenseInfo,
                                        licenseParams: UdlLicenseParams(
                                          derivations: 'Allowed',
                                        ),
                                      ),
                                    );
                                context
                                    .read<DriveDetailCubit>()
                                    .forceDisableMultiselect = true;
                              },
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            );
          } else {
            return const SizedBox();
          }
        });
      },
    );
  }

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colors.themeInputPlaceholder;
}
