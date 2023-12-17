import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/license/license_types.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

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
    final fileItems = selectedItems.whereType<FileDataTableItem>().toList();

    return BlocConsumer<FsEntryLicenseBloc, FsEntryLicenseState>(
      listener: (context, state) {
        if (state is FsEntryLicenseLoadInProgress) {
          showProgressDialog(
            context,
            title: 'Licensing Items',
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
          final licenseInfo =
              context.read<FsEntryLicenseBloc>().selectFormLicenseInfo;
          if (state is FsEntryLicenseSelecting) {
            return ArDriveStandardModal(
              width: kMediumDialogWidth,
              title:
                  "Add license to ${fileItems.length} file${fileItems.length > 1 ? 's' : ''}",
              // TODO: Localize
              // title: appLocalizationsOf(context).renameFolderEmphasized,
              content: SizedBox(
                height: 225,
                width: kMediumDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    LicenseFileList(fileList: fileItems),
                    const Divider(),
                    ReactiveForm(
                      formGroup: context.watch<FsEntryLicenseBloc>().selectForm,
                      child: ReactiveDropdownField(
                        formControlName: 'licenseType',
                        decoration: InputDecoration(
                          label: Text(
                            'License Type',
                            // TODO: Localize
                            // appLocalizationsOf(context).licenseType,
                            style: ArDriveTheme.of(context)
                                .themeData
                                .textFieldTheme
                                .inputTextStyle
                                .copyWith(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeFgDisabled,
                                  fontSize: 16,
                                ),
                          ),
                          focusedBorder: InputBorder.none,
                        ),
                        showErrors: (control) =>
                            control.dirty && control.invalid,
                        validationMessages:
                            kValidationMessages(appLocalizationsOf(context)),
                        items: licenseInfoMap.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.name),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(),
                  title: appLocalizationsOf(context).cancelEmphasized,
                ),
                ModalAction(
                  action: () => context
                      .read<FsEntryLicenseBloc>()
                      .add(const FsEntryLicenseSelect()),
                  title: appLocalizationsOf(context).nextEmphasized,
                ),
              ],
            );
          } else if (state is FsEntryLicenseConfiguring) {
            return ArDriveStandardModal(
              title: 'Configuring ${licenseInfo.name}',
              content: const SizedBox(),
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(),
                  title: appLocalizationsOf(context).cancelEmphasized,
                ),
                ModalAction(
                  action: () => context
                      .read<FsEntryLicenseBloc>()
                      .add(const FsEntryLicenseSubmitConfiguration()),
                  title: appLocalizationsOf(context).nextEmphasized,
                ),
              ],
            );
          } else if (state is FsEntryLicenseReviewing) {
            return ArDriveStandardModal(
              title: 'Reviewing ${licenseInfo.name}',
              content: const SizedBox(),
              actions: [
                licenseInfo.hasParams
                    ? ModalAction(
                        action: () => context
                            .read<FsEntryLicenseBloc>()
                            .add(const FsEntryLicenseSelect()),
                        title: appLocalizationsOf(context).backEmphasized,
                      )
                    : ModalAction(
                        action: () => Navigator.of(context).pop(),
                        title: appLocalizationsOf(context).cancelEmphasized,
                      ),
                ModalAction(
                  action: () => context
                      .read<FsEntryLicenseBloc>()
                      .add(const FsEntryLicenseReviewConfirm()),
                  title: appLocalizationsOf(context).confirmEmphasized,
                ),
              ],
            );
          } else {
            return const SizedBox();
          }
        });
      },
    );
  }
}

class LicenseFileList extends StatelessWidget {
  final List<FileDataTableItem> fileList;

  const LicenseFileList({
    super.key,
    required this.fileList,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 100),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: fileList.length,
        itemBuilder: (context, index) => Padding(
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
                  fileList[index].name,
                  style: ArDriveTypography.body.inputNormalRegular(
                    color: _colorDisabled(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colors.themeInputPlaceholder;
}
