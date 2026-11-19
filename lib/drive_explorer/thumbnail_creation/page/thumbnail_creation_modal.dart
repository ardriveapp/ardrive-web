import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/components/payment_required_notice.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/drive_explorer/thumbnail_creation/bloc/thumbnail_creation_bloc.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ThumbnailCreationModal extends StatelessWidget {
  const ThumbnailCreationModal({super.key, required this.fileDataTableItem});

  final FileDataTableItem fileDataTableItem;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => context.read<ThumbnailRepository>(),
      child: BlocProvider(
        create: (context) {
          return ThumbnailCreationBloc(
              thumbnailRepository: context.read<ThumbnailRepository>());
        },
        child: _ThumbnailCreationModal(
          fileDataTableItem: fileDataTableItem,
        ),
      ),
    );
  }
}

class _ThumbnailCreationModal extends StatelessWidget {
  const _ThumbnailCreationModal({required this.fileDataTableItem});

  final FileDataTableItem fileDataTableItem;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    void create() => context
        .read<ThumbnailCreationBloc>()
        .add(CreateThumbnail(fileDataTableItem: fileDataTableItem));

    return BlocConsumer<ThumbnailCreationBloc, ThumbnailCreationState>(
      listener: (context, state) {
        if (state is ThumbnailCreationSuccess) {
          context.read<DriveDetailCubit>().refreshDriveDataTable();
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        final busy = state is ThumbnailCreationLoading;
        return ArDriveStandardModalNew(
          title: l10n.createThumbnail,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.createThumbnailDescription,
                style: typography.paragraphNormal(color: colorTokens.textMid),
              ),
              if (state is ThumbnailCreationError)
                Padding(
                  padding: const EdgeInsets.only(top: ArDriveSpacing.md),
                  child: state.isPaymentError
                      ? const PaymentRequiredNotice()
                      : ArDriveNotice(
                          type: ArDriveNoticeType.error,
                          title: l10n.couldNotCreateThumbnailTitle,
                          message: l10n.actionFailedTryAgain,
                          actionLabel: l10n.tryAgain,
                          onAction: create,
                        ),
                ),
            ],
          ),
          actions: [
            ModalAction.close(
              action: () => Navigator.of(context).pop(),
              title: l10n.cancel,
              isEnable: !busy,
            ),
            ModalAction(
              isEnable: true,
              isLoading: busy,
              action: create,
              title: l10n.createThumbnail,
            ),
          ],
        );
      },
    );
  }
}
