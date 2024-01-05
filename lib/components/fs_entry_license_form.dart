import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/license/license_types.dart';
import 'package:ardrive/services/license/licenses/udl.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
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
            crypto: ArDriveCrypto(),
            driveId: driveId,
            selectedItems: selectedItems,
            arweave: context.read<ArweaveService>(),
            turboUploadService: context.read<TurboUploadService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            licenseService: context.read<LicenseService>(),
          )..add(const FsEntryLicenseInitial()),
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
            title: 'Licensing Items',
            // TODO: Localize
            // title: appLocalizationsOf(context).licensingItemsEmphasized,
          );
        } else if (state is FsEntryLicenseSuccess ||
            state is FsEntryLicenseFailure) {
          // close progressDialog
          Navigator.pop(context);
        } else if (state is FsEntryLicenseComplete) {
          // close LicenseForm
          Navigator.pop(context);
        } else if (state is FsEntryLicenseWalletMismatch) {
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        return Builder(builder: (context) {
          final licenseMeta =
              context.read<FsEntryLicenseBloc>().selectFormLicenseMeta;
          if (state is FsEntryLicenseNoFiles) {
            return ArDriveCard(
              height: 350,
              width: kMediumDialogWidth,
              contentPadding: EdgeInsets.zero,
              content: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.only(left: 16, right: 16),
                    width: double.infinity,
                    height: 37,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ArDriveClickArea(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Align(
                              alignment: Alignment.centerRight,
                              child: ArDriveIcon(
                                icon: ArDriveIconsData.x,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 37,
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ArDriveIcon(
                            icon: ArDriveIconsData.close_circle,
                            size: 64,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeErrorOnEmphasis,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            // TODO: Localize
                            'No valid file to license.',
                            textAlign: TextAlign.center,
                            style: ArDriveTypography.headline.headline4Bold(),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            // TODO: Localize
                            'Please try again with another file.',
                            textAlign: TextAlign.center,
                            style: ArDriveTypography.body.buttonLargeRegular(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                            ),
                          ),
                          const SizedBox(height: 32),
                          ArDriveButton(
                            maxHeight: 36,
                            backgroundColor: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                            fontStyle: ArDriveTypography.body
                                .buttonNormalBold(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeAccentSubtle,
                                )
                                .copyWith(fontWeight: FontWeight.bold),
                            text: appLocalizationsOf(context).close,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          } else if (state is FsEntryLicenseSelecting) {
            final filesToLicense =
                context.read<FsEntryLicenseBloc>().filesToLicense;
            return ArDriveStandardModal(
              title:
                  "Add license to ${filesToLicense!.length} file${filesToLicense.length > 1 ? 's' : ''}",
              width: kMediumDialogWidth,
              // TODO: Localize
              // title: appLocalizationsOf(context).renameFolderEmphasized,
              content: SizedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    LicenseFileList(fileList: filesToLicense),
                    const SizedBox(height: 16),
                    const Divider(height: 24),
                    ReactiveForm(
                      formGroup: context.watch<FsEntryLicenseBloc>().selectForm,
                      child: ReactiveDropdownField(
                        formControlName: 'licenseType',
                        decoration: InputDecoration(
                          label: Text(
                            'License',
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
                        items: licenseMetaMap.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child:
                                    Text('${value.name} (${value.shortName})'),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const Divider(height: 32),
                    Text(
                      // TODO: Localize
                      'Cost: 0 AR',
                      style: ArDriveTypography.body.buttonLargeRegular(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                    ),
                    Text(
                      // TODO: Localize
                      'Free for now, maybe paid later.',
                      style: ArDriveTypography.body.captionRegular(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgSubtle,
                      ),
                    ),
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
              title:
                  'Configuring ${licenseMeta.name} (${licenseMeta.shortName})',
              width: kMediumDialogWidth,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  LicenseFileList(
                      fileList:
                          context.read<FsEntryLicenseBloc>().filesToLicense!),
                  const SizedBox(height: 16),
                  const Divider(height: 24),
                  context
                              .read<FsEntryLicenseBloc>()
                              .selectFormLicenseMeta
                              .licenseType ==
                          LicenseType.udl
                      ? UdlParamsForm(
                          formGroup:
                              context.watch<FsEntryLicenseBloc>().udlForm,
                        )
                      : const Text('Unsupported license type'),
                ],
              ),
              actions: [
                ModalAction(
                  action: () => context
                      .read<FsEntryLicenseBloc>()
                      .add(const FsEntryLicenseConfigurationBack()),
                  title: appLocalizationsOf(context).backEmphasized,
                ),
                ModalAction(
                  action: () => context
                      .read<FsEntryLicenseBloc>()
                      .add(const FsEntryLicenseConfigurationSubmit()),
                  title: appLocalizationsOf(context).nextEmphasized,
                ),
              ],
            );
          } else if (state is FsEntryLicenseReviewing) {
            return ArDriveStandardModal(
              title: 'Review',
              width: kMediumDialogWidth,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  LicenseFileList(
                      fileList:
                          context.read<FsEntryLicenseBloc>().filesToLicense!),
                  const SizedBox(height: 16),
                  const Divider(height: 24),
                  const SizedBox(height: 16),
                  LicenseSummary(
                    licenseMeta: licenseMeta,
                    licenseParams:
                        context.read<FsEntryLicenseBloc>().licenseParams,
                  ),
                  const Divider(height: 32),
                  Text(
                    // TODO: Localize
                    'Cost: 0 AR',
                    style: ArDriveTypography.body.buttonLargeRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
                    ),
                  ),
                  Text(
                    // TODO: Localize
                    'Free for now, maybe paid later.',
                    style: ArDriveTypography.body.captionRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgSubtle,
                    ),
                  ),
                ],
              ),
              actions: [
                ModalAction(
                  action: () => context
                      .read<FsEntryLicenseBloc>()
                      .add(const FsEntryLicenseReviewBack()),
                  title: appLocalizationsOf(context).backEmphasized,
                ),
                ModalAction(
                  action: () => context
                      .read<FsEntryLicenseBloc>()
                      .add(const FsEntryLicenseReviewConfirm()),
                  title: appLocalizationsOf(context).confirmEmphasized,
                ),
              ],
            );
          } else if (state is FsEntryLicenseSuccess) {
            return ArDriveCard(
              height: 400,
              width: kMediumDialogWidth,
              contentPadding: EdgeInsets.zero,
              content: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.only(left: 16, right: 16),
                    width: double.infinity,
                    height: 77,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ArDriveClickArea(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Align(
                              alignment: Alignment.centerRight,
                              child: ArDriveIcon(
                                icon: ArDriveIconsData.x,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 77,
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ArDriveIcon(
                            icon: ArDriveIconsData.check_cirle,
                            size: 64,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeSuccessEmphasis,
                          ),
                          const SizedBox(height: 16),
                          Flexible(
                            child: Text(
                              // TODO: Localize
                              'You little licenser, you.',
                              style: ArDriveTypography.headline.headline4Bold(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            // TODO: Localize
                            'Your files have successfully been licensed. You can go ahead and do your thing now.',
                            textAlign: TextAlign.center,
                            style: ArDriveTypography.body.buttonLargeRegular(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                            ),
                          ),
                          const SizedBox(height: 32),
                          ArDriveButton(
                            maxHeight: 36,
                            backgroundColor: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                            fontStyle: ArDriveTypography.body
                                .buttonNormalBold(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeAccentSubtle,
                                )
                                .copyWith(fontWeight: FontWeight.bold),
                            text: appLocalizationsOf(context).close,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          } else if (state is FsEntryLicenseFailure) {
            return ArDriveCard(
              height: 400,
              width: kMediumDialogWidth,
              contentPadding: EdgeInsets.zero,
              content: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.only(left: 16, right: 16),
                    width: double.infinity,
                    height: 77,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ArDriveClickArea(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Align(
                              alignment: Alignment.centerRight,
                              child: ArDriveIcon(
                                icon: ArDriveIconsData.x,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 77,
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ArDriveIcon(
                            icon: ArDriveIconsData.close_circle,
                            size: 64,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeErrorOnEmphasis,
                          ),
                          const SizedBox(height: 16),
                          Flexible(
                            child: Text(
                              // TODO: Localize
                              'No dice.',
                              style: ArDriveTypography.headline.headline4Bold(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            // TODO: Localize
                            'Your attempted licensing failed, want to try again now?',
                            textAlign: TextAlign.center,
                            style: ArDriveTypography.body.buttonLargeRegular(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                            ),
                          ),
                          const SizedBox(height: 32),
                          ArDriveButton(
                            maxHeight: 36,
                            backgroundColor: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                            fontStyle: ArDriveTypography.body
                                .buttonNormalBold(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeAccentSubtle,
                                )
                                .copyWith(fontWeight: FontWeight.bold),
                            text: appLocalizationsOf(context).tryAgain,
                            onPressed: () => context
                                .read<FsEntryLicenseBloc>()
                                .add(const FsEntryLicenseFailureTryAgain()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
  final List<FileEntry> fileList;

  const LicenseFileList({
    super.key,
    required this.fileList,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 100,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: fileList.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 4,
          ),
          child: Text(
            fileList[index].name,
            style: ArDriveTypography.body.inputNormalRegular(
              color: _colorDisabled(context),
            ),
          ),
        ),
      ),
    );
  }

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colors.themeInputPlaceholder;
}

class UdlParamsForm extends StatelessWidget {
  final FormGroup formGroup;

  const UdlParamsForm({super.key, required this.formGroup});

  @override
  Widget build(BuildContext context) {
    final inputBorder = OutlineInputBorder(
      borderSide: BorderSide(
        color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
      ),
      borderRadius: BorderRadius.circular(4),
    );

    return ReactiveForm(
        formGroup: formGroup,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ReactiveTextField(
                    formControlName: 'licenseFeeAmount',
                    cursorColor: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                    keyboardType: TextInputType.number,
                    showErrors: (control) => control.dirty && control.invalid,
                    decoration: InputDecoration(
                      label: Text(
                        'License Fee',
                        // TODO: Localize
                        // appLocalizationsOf(context).udlLicenseFee,
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
                      border: inputBorder,
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder,
                    ),
                    style: const TextStyle(height: 1.5),
                  ),
                ),
                Container(
                  width: kMediumDialogWidth * 0.5,
                  padding: const EdgeInsets.only(left: 24),
                  child: ReactiveDropdownField(
                    formControlName: 'licenseFeeCurrency',
                    decoration: InputDecoration(
                      label: Text(
                        appLocalizationsOf(context).currency,
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
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder,
                    ),
                    showErrors: (control) => control.dirty && control.invalid,
                    validationMessages:
                        kValidationMessages(appLocalizationsOf(context)),
                    items: udlCurrencyValues.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
            ReactiveDropdownField(
              formControlName: 'commercialUse',
              decoration: InputDecoration(
                label: Text(
                  'Commercial Use',
                  // TODO: Localize
                  // appLocalizationsOf(context).udlCommercialUse,
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
                enabledBorder: inputBorder,
                focusedBorder: inputBorder,
              ),
              showErrors: (control) => control.dirty && control.invalid,
              validationMessages:
                  kValidationMessages(appLocalizationsOf(context)),
              items: udlCommercialUseValues.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
            ),
            ReactiveDropdownField(
              formControlName: 'derivations',
              decoration: InputDecoration(
                label: Text(
                  'Derivations',
                  // TODO: Localize
                  // appLocalizationsOf(context).udlDerivations,
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
                enabledBorder: inputBorder,
                focusedBorder: inputBorder,
              ),
              showErrors: (control) => control.dirty && control.invalid,
              validationMessages:
                  kValidationMessages(appLocalizationsOf(context)),
              items: udlDerivationValues.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
            ),
          ]
              .expand(
                (element) => [element, const SizedBox(height: 32)],
              )
              .toList(),
        ));
  }
}

class LicenseSummary extends StatelessWidget {
  final LicenseMeta licenseMeta;
  final LicenseParams? licenseParams;
  late final Map<String, String> summaryItems;

  LicenseSummary({
    super.key,
    required this.licenseMeta,
    this.licenseParams,
  }) {
    summaryItems = licenseParams is UdlLicenseParams
        ? udlLicenseSummary(licenseParams as UdlLicenseParams)
        : {};
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // TODO: Localize
          'License',
          style: ArDriveTypography.body.smallRegular(
            color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
          ),
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${licenseMeta.name} (${licenseMeta.shortName})',
                style: ArDriveTypography.body.buttonLargeBold(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                ),
              ),
              const TextSpan(text: '   '),
              TextSpan(
                text: 'View',
                style: ArDriveTypography.body
                    .buttonLargeRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgSubtle,
                    )
                    .copyWith(
                      decoration: TextDecoration.underline,
                    ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () async {
                    final url =
                        'https://viewblock.io/arweave/tx/${licenseMeta.licenseDefinitionTxId}';
                    await openUrl(url: url);
                  },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ...summaryItems.entries.expand(
          (entry) => [
            Text(
              entry.key,
              style: ArDriveTypography.body.smallRegular(
                color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
              ),
            ),
            Text(
              entry.value,
              style: ArDriveTypography.body.buttonLargeBold(
                color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              ),
            ),
            const SizedBox(height: 24),
          ],
        )
      ],
    );
  }

  Map<String, String> udlLicenseSummary(UdlLicenseParams udlLicenseParams) {
    final summary = <String, String>{};

    if (udlLicenseParams.licenseFeeAmount != null) {
      summary['License Fee'] = '${udlLicenseParams.licenseFeeAmount}';
      summary['License Currency'] =
          udlCurrencyValues[udlLicenseParams.licenseFeeCurrency]!;
    }
    if (udlLicenseParams.commercialUse != UdlCommercialUse.unspecified) {
      summary['Commercial Use'] =
          udlCommercialUseValues[udlLicenseParams.commercialUse]!;
    }
    if (udlLicenseParams.derivations != UdlDerivation.unspecified) {
      summary['Derivations'] =
          udlDerivationValues[udlLicenseParams.derivations]!;
    }

    return summary;
  }
}
