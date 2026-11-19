import 'dart:async';

import 'package:ardrive/components/reactive_select_field.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/turbo_credits_funding.dart';
import 'package:ardrive/components/upload_review_dialog.dart';
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/components/license/cc_type_form.dart';
import 'package:ardrive/components/license/udl_params_form.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
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
    // Only Cancel or the X close it, and both wait while the license is
    // written: a click outside would leave the write running unseen.
    barrierDismissible: false,
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
            costReader: MetadataWriteCostReader(
              payments: context.read<PaymentService>(),
              turbo: context.read<TurboUploadService>(),
              arweave: context.read<ArweaveService>(),
            ),
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

/// Add license, on one screen: the files, the license and its own settings,
/// and what writing it costs. It was four: pick a category, configure it,
/// review it, then a progress dialog on top.
class _FsEntryLicenseFormState extends State<FsEntryLicenseForm> {
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _settle;

  /// A change on screen the bloc has not applied yet: Add license waits for
  /// it, so it never writes the license from before the change.
  var _pending = false;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<FsEntryLicenseBloc>();
    // A change to the license or its settings prices the write again, once
    // typing in the fee settles.
    void changed(Object? _) {
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        bloc.add(const FsEntryLicenseSettingsChanged());
        setState(() => _pending = false);
      });
      if (mounted) setState(() => _pending = true);
    }

    for (final form in [
      bloc.categoryForm,
      bloc.udlParamsForm,
      bloc.ccTypeForm
    ]) {
      _subscriptions.add(form.valueChanges.listen(changed));
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FsEntryLicenseBloc, FsEntryLicenseState>(
      listener: (context, state) {
        if (state is FsEntryLicenseSuccess) {
          context.read<DriveDetailCubit>().refreshDriveDataTable();
        } else if (state is FsEntryLicenseComplete) {
          context.read<DriveDetailCubit>().refreshDriveDataTable();
          Navigator.pop(context);
        } else if (state is FsEntryLicenseWalletMismatch) {
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        final l10n = appLocalizationsOf(context);
        final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
        final bloc = context.read<FsEntryLicenseBloc>();

        if (state is FsEntryLicenseNoFiles) {
          return _LicenseResult(
            icon: ArDriveIcons.closeCircle(
              size: 24,
              color: colorTokens.statusErrorFg,
            ),
            title: l10n.noFileToLicenseTitle,
            message: l10n.noFileToLicenseMessage,
            actions: [
              ModalAction.close(
                action: () => Navigator.of(context).pop(),
                title: l10n.close,
              ),
            ],
          );
        } else if (state is FsEntryLicenseReviewing) {
          return _review(context, state);
        } else if (state is FsEntryLicenseSuccess) {
          return _LicenseResult(
            icon: ArDriveIcons.checkCirle(
              size: 24,
              color: colorTokens.statusSuccessFg,
            ),
            title: l10n.licenseAddedTitle,
            message: l10n.licenseAddedMessage(
              bloc.selectedLicenseMeta.shortName,
              bloc.filesToLicense?.length ?? 0,
            ),
            actions: [
              ModalAction.close(
                action: () => Navigator.of(context).pop(),
                title: l10n.close,
              ),
            ],
          );
        } else if (state is FsEntryLicenseLoadInProgress) {
          // Finding the files to license: the dialog itself waits.
          return ProgressDialog(title: l10n.addLicense);
        } else {
          return const SizedBox();
        }
      },
    );
  }

  Widget _review(BuildContext context, FsEntryLicenseReviewing state) {
    final l10n = appLocalizationsOf(context);
    final bloc = context.read<FsEntryLicenseBloc>();
    final files = bloc.filesToLicense ?? const <FileEntry>[];
    final category = bloc.selectedLicenseCategory;

    final settings = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReactiveForm(
          formGroup: bloc.categoryForm,
          child: ReactiveArDriveSelectField<LicenseCategory>(
            formControlName: 'licenseCategory',
            label: l10n.licenseHeading,
            showErrors: (control) => control.dirty && control.invalid,
            validationMessages: kValidationMessages(l10n),
            choices: [
              for (final value in LicenseCategory.values)
                ArDriveChoice(
                  value: value,
                  label: '${licenseCategoryNames[value]}',
                ),
            ],
          ),
        ),
        const SizedBox(height: ArDriveSpacing.md),
        // The chosen license's own settings, where its choice is.
        if (category == LicenseCategory.udl)
          UdlParamsForm(
            formGroup: bloc.udlParamsForm,
            onChangeLicenseFee: () {},
          )
        else if (category == LicenseCategory.cc)
          CcTypeForm(formGroup: bloc.ccTypeForm),
      ],
    );

    return UploadReviewDialog(
      title: l10n.addLicense,
      destination: l10n.licenseReviewFiles(files.length),
      files: const [],
      leading: [
        LicenseFileList(fileList: files),
        const SizedBox(height: ArDriveSpacing.lg),
        // Read-only while the license is written, to the keyboard too.
        AbsorbPointer(
          absorbing: state.busy,
          child: ExcludeFocus(excluding: state.busy, child: settings),
        ),
      ],
      extras: [
        if (state.failed)
          SizedBox(
            width: double.infinity,
            child: ArDriveNotice(
              type: ArDriveNoticeType.error,
              title: l10n.licenseFailedTitle,
              message: l10n.licenseFailedMessage,
            ),
          ),
      ],
      summary: state.summary,
      costPendingReason: !state.incomplete
          ? null
          : category == LicenseCategory.cc
              ? l10n.licenseChooseTypeForCost
              : l10n.licenseFixSettingsForCost,
      primaryLabel: l10n.addLicense,
      primaryEnabled: !_pending,
      primaryBusy: state.busy,
      subject: ReviewCostSubject.change,
      priceUnavailableMessage:
          state.pricingFailed ? l10n.priceUnavailableTryAgain : null,
      onUpload: (_) => bloc.add(const FsEntryLicenseReviewConfirm()),
      onCancel: () => Navigator.of(context).pop(),
      funding: TurboCreditsFunding(
        context,
        onRefresh: () => bloc.add(const FsEntryLicenseCostRefresh()),
      ),
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
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    // The files the license goes on, in a card like an upload's, readable:
    // they were drawn in the disabled colour, the faintest text on screen.
    return Container(
      constraints: const BoxConstraints(maxHeight: 44 * 4.5),
      decoration: BoxDecoration(
        color: colorTokens.containerRaised,
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: fileList.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          indent: ArDriveSpacing.sm,
          endIndent: ArDriveSpacing.sm,
          color: colorTokens.strokeLow,
        ),
        itemBuilder: (context, index) => SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ArDriveSpacing.sm),
            child: Row(
              children: [
                getIconForContentType(
                  fileList[index].dataContentType ?? '',
                  size: 18,
                  color: colorTokens.iconMid,
                ),
                const SizedBox(width: ArDriveSpacing.sm),
                Expanded(
                  child: Text(
                    fileList[index].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
