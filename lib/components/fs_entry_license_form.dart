import 'package:ardrive/components/reactive_select_field.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/turbo_payment_required_dialog.dart';
import 'package:ardrive/components/license/cc_type_form.dart';
import 'package:ardrive/components/license/udl_params_form.dart';
import 'package:ardrive/components/license_summary.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

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

class FsEntryLicenseForm extends StatefulWidget {
  final List<ArDriveDataTableItem> selectedItems;

  const FsEntryLicenseForm({
    super.key,
    required this.selectedItems,
  });

  @override
  State<FsEntryLicenseForm> createState() => _FsEntryLicenseFormState();
}

class _FsEntryLicenseFormState extends State<FsEntryLicenseForm> {
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FsEntryLicenseBloc, FsEntryLicenseState>(
      listener: (context, state) {
        if (state is FsEntryLicenseLoadInProgress) {
          showProgressDialog(
            context,
            title: 'Licensing items',
            // TODO: Localize
            // title: appLocalizationsOf(context).licensingItemsEmphasized,
          );
        } else if (state is FsEntryLicenseSuccess ||
            state is FsEntryLicenseFailure) {
          // close progressDialog
          context.read<DriveDetailCubit>().refreshDriveDataTable();
          Navigator.pop(context);
        } else if (state is FsEntryLicenseComplete) {
          // close LicenseForm

          context.read<DriveDetailCubit>().refreshDriveDataTable();
          Navigator.pop(context);
        } else if (state is FsEntryLicenseWalletMismatch) {
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        return Builder(builder: (context) {
          final licenseMeta =
              context.read<FsEntryLicenseBloc>().selectedLicenseMeta;
          final typography = ArDriveTypographyNew.of(context);
          final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
          final divider = Divider(color: colorTokens.strokeLow, height: 32);
          final cost = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // TODO: Localize
                'Cost: 0 AR',
                style: typography.paragraphLarge(color: colorTokens.textHigh),
              ),
              Text(
                // TODO: Localize
                'Free for now, maybe paid later.',
                style: typography.paragraphSmall(color: colorTokens.textLow),
              ),
            ],
          );

          if (state is FsEntryLicenseNoFiles) {
            return _LicenseResult(
              icon: ArDriveIcons.closeCircle(
                size: 24,
                color: colorTokens.statusErrorFg,
              ),
              // TODO: Localize
              title: 'No valid file to license.',
              // TODO: Localize
              message: 'Please try again with another file.',
              actions: [
                ModalAction.dismiss(
                  action: () => Navigator.of(context).pop(),
                  title: appLocalizationsOf(context).close,
                ),
              ],
            );
          } else if (state is FsEntryLicenseSelecting) {
            final filesToLicense =
                context.read<FsEntryLicenseBloc>().filesToLicense;
            return ArDriveStandardModalNew(
              title:
                  "Add license to ${filesToLicense!.length} file${filesToLicense.length > 1 ? 's' : ''}",
              width: kMediumDialogWidth,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LicenseFileList(fileList: filesToLicense),
                  divider,
                  ReactiveForm(
                    formGroup: context.watch<FsEntryLicenseBloc>().categoryForm,
                    child: ReactiveArDriveSelectField<LicenseCategory>(
                      formControlName: 'licenseCategory',
                      // TODO: Localize
                      // appLocalizationsOf(context).licenseType,
                      label: 'License',
                      showErrors: (control) => control.dirty && control.invalid,
                      validationMessages:
                          kValidationMessages(appLocalizationsOf(context)),
                      choices: [
                        for (final value in LicenseCategory.values)
                          ArDriveChoice(
                            value: value,
                            label: '${licenseCategoryNames[value]}',
                          ),
                      ],
                    ),
                  ),
                  divider,
                  cost,
                ],
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
            final licenseCategory =
                context.read<FsEntryLicenseBloc>().selectedLicenseCategory;
            final modalTitle = licenseCategory == LicenseCategory.udl
                ? 'Configure Universal Data License'
                : licenseCategory == LicenseCategory.cc
                    ? 'Configure Creative Commons license'
                    : 'Unsupported license type';
            final licenseBloc = context.watch<FsEntryLicenseBloc>();
            final FormGroup activeForm = licenseCategory == LicenseCategory.cc
                ? licenseBloc.ccTypeForm
                : licenseBloc.udlParamsForm;
            // Rebuilt as the form on screen changes, so Next follows it.
            return ReactiveForm(
              formGroup: activeForm,
              child: ReactiveFormConsumer(
                builder: (context, _, __) => ArDriveStandardModalNew(
                  title: modalTitle,
                  width: kLargeDialogWidth,
                  // The UDL form is long: it scrolls under the title and the
                  // actions stay in view.
                  scrollableContent: true,
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LicenseFileList(
                          fileList: context
                              .read<FsEntryLicenseBloc>()
                              .filesToLicense!),
                      divider,
                      licenseCategory == LicenseCategory.udl
                          ? UdlParamsForm(
                              onChangeLicenseFee: () {
                                setState(() {});
                              },
                              formGroup: context
                                  .watch<FsEntryLicenseBloc>()
                                  .udlParamsForm,
                            )
                          : licenseCategory == LicenseCategory.cc
                              ? CcTypeForm(
                                  formGroup: context
                                      .watch<FsEntryLicenseBloc>()
                                      .ccTypeForm,
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
                      // The form on screen, not always the UDL one: with no
                      // Creative Commons type preselected, gating on the UDL
                      // form let a CC license go on with none chosen.
                      isEnable: activeForm.valid,
                      action: () => context
                          .read<FsEntryLicenseBloc>()
                          .add(const FsEntryLicenseConfigurationSubmit()),
                      title: appLocalizationsOf(context).nextEmphasized,
                    ),
                  ],
                ),
              ),
            );
          } else if (state is FsEntryLicenseReviewing) {
            return ArDriveStandardModalNew(
              title: 'Review',
              width: kMediumDialogWidth,
              scrollableContent: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LicenseFileList(
                      fileList:
                          context.read<FsEntryLicenseBloc>().filesToLicense!),
                  divider,
                  LicenseSummary(
                    licenseState: LicenseState(
                        meta: licenseMeta,
                        params:
                            context.read<FsEntryLicenseBloc>().licenseParams),
                  ),
                  divider,
                  cost,
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
            return _LicenseResult(
              icon: ArDriveIcons.checkCirle(
                size: 24,
                color: colorTokens.statusSuccessFg,
              ),
              // TODO: Localize
              title: 'You little licenser, you.',
              // TODO: Localize
              message:
                  'Your files have successfully been licensed. You can go ahead and do your thing now.',
              actions: [
                ModalAction.dismiss(
                  action: () => Navigator.of(context).pop(),
                  title: appLocalizationsOf(context).close,
                ),
              ],
            );
          } else if (state is FsEntryLicenseFailure) {
            return _LicenseResult(
              icon: ArDriveIcons.closeCircle(
                size: 24,
                color: colorTokens.statusErrorFg,
              ),
              title: state.isPaymentError
                  ? appLocalizationsOf(context).freeAllowanceUsedUpTitle
                  // TODO: Localize
                  : 'No dice.',
              message: state.isPaymentError
                  ? appLocalizationsOf(context).freeAllowanceUsedUpDescription
                  // TODO: Localize
                  : 'Your attempted licensing failed, want to try again now?',
              actions: [
                ModalAction.dismiss(
                  action: () => Navigator.of(context).pop(),
                  title: appLocalizationsOf(context).close,
                ),
                ModalAction(
                  action: () {
                    if (state.isPaymentError) {
                      showTurboPaymentRequiredDialog(context);
                    } else {
                      context
                          .read<FsEntryLicenseBloc>()
                          .add(const FsEntryLicenseFailureTryAgain());
                    }
                  },
                  title: state.isPaymentError
                      ? appLocalizationsOf(context).buyCredits
                      : appLocalizationsOf(context).tryAgain,
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

/// The end of a licensing attempt: a standard dialog with the outcome's icon
/// beside what happened. These were hand-made cards with their own close
/// cross and an inverted button, unlike every other dialog.
class _LicenseResult extends StatelessWidget {
  const _LicenseResult({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
  });

  final Widget icon;
  final String title;
  final String message;
  final List<ModalAction> actions;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveStandardModalNew(
      title: title,
      width: kMediumDialogWidth,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: icon),
          const SizedBox(width: ArDriveSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: typography.paragraphNormal(color: colorTokens.textMid),
            ),
          ),
        ],
      ),
      actions: actions,
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
            style: ArDriveTypographyNew.of(context).paragraphLarge(
              color: _colorDisabled(context),
            ),
          ),
        ),
      ),
    );
  }

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colorTokens.textLow;
}
