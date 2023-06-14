import 'dart:ui';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/cost_estimate.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';

class DriveFileDropZone extends StatefulWidget {
  final String driveId;
  final String folderId;

  const DriveFileDropZone({
    Key? key,
    required this.driveId,
    required this.folderId,
  }) : super(key: key);

  @override
  DriveFileDropZoneState createState() => DriveFileDropZoneState();
}

class DriveFileDropZoneState extends State<DriveFileDropZone> {
  late DropzoneViewController controller;
  bool isHovering = false;
  bool isCurrentlyShown = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 128, horizontal: 128),
      child: IgnorePointer(
        child: Stack(
          children: [
            BackdropFilter(
              filter: isHovering
                  ? ImageFilter.blur(sigmaX: 2, sigmaY: 2)
                  : ImageFilter.blur(sigmaX: 0.1, sigmaY: 0.1),
              blendMode: BlendMode.srcOver,
              child: ArDriveDropZone(
                  withBorder: false,
                  onDragEntered: () => setState(() => isHovering = true),
                  key: const Key('dropZone'),
                  onDragExited: () => setState(() => isHovering = false),
                  onDragDone: (files) => _onDrop(
                        files,
                        driveId: widget.driveId,
                        parentFolderId: widget.folderId,
                        context: context,
                      ),
                  onError: (e) async {
                    if (e is DropzoneWrongInputException) {
                      await showAnimatedDialog(
                        context,
                        content: ArDriveStandardModal(
                          title: appLocalizationsOf(context).error,
                          content: Text(
                            appLocalizationsOf(context).errorDragAndDropFolder,
                          ),
                          actions: [
                            ModalAction(
                              action: () => Navigator.of(context).pop(false),
                              title: appLocalizationsOf(context).ok,
                            ),
                          ],
                        ),
                        barrierDismissible: true,
                      ).then((value) => isCurrentlyShown = false);
                    }

                    return _onLeave();
                  },
                  child: isHovering
                      ? _buildDropZoneOnHover()
                      : const SizedBox.expand()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDrop(
    List<IOFile> files, {
    required BuildContext context,
    required String driveId,
    required String parentFolderId,
  }) async {
    if (!isCurrentlyShown) {
      isCurrentlyShown = true;
      _onLeave();
      final selectedFiles = files
          .map((e) => UploadFile(
                ioFile: e,
                parentFolderId: parentFolderId,
              ))
          .toList();

      // ignore: use_build_context_synchronously
      await showCongestionDependentModalDialog(
        context,
        () => showAnimatedDialog(
          context,
          content: BlocProvider<UploadCubit>(
            create: (context) => UploadCubit(
              arCostCalculator: UploadCostEstimateCalculatorForAR(
                arweaveService: context.read<ArweaveService>(),
                pstService: context.read<PstService>(),
              ),
              turboUploadCostCalculator: TurboUploadCostCalculator(
                priceEstimator: TurboPriceEstimator(
                  costCalculator: TurboCostCalculator(
                    paymentService: context.read<PaymentService>(),
                  ),
                  paymentService: context.read<PaymentService>(),
                ),
                turboCostCalculator: TurboCostCalculator(
                  paymentService: context.read<PaymentService>(),
                ),
                pstService: context.read<PstService>(),
              ),
              uploadFileChecker: context.read<UploadFileChecker>(),
              uploadPlanUtils: UploadPlanUtils(
                crypto: ArDriveCrypto(),
                arweave: context.read<ArweaveService>(),
                turboUploadService: context.read<TurboUploadService>(),
                driveDao: context.read<DriveDao>(),
              ),
              driveId: driveId,
              parentFolderId: parentFolderId,
              files: selectedFiles,
              arweave: context.read<ArweaveService>(),
              turbo: context.read<TurboUploadService>(),
              pst: context.read<PstService>(),
              profileCubit: context.read<ProfileCubit>(),
              driveDao: context.read<DriveDao>(),
              auth: context.read<ArDriveAuth>(),
              turboBalanceRetriever: TurboBalanceRetriever(
                paymentService: context.read<PaymentService>(),
              ),
            )..startUploadPreparation(),
            child: UploadForm(),
          ),
          barrierDismissible: false,
        ).then((value) => isCurrentlyShown = false),
      );
    }
  }

  void _onHover() => setState(() => isHovering = true);
  void _onLeave() => setState(() => isHovering = false);

  Widget _buildDropZoneOnHover() => Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          width: MediaQuery.of(context).size.width / 1.5,
          height: MediaQuery.of(context).size.width / 3,
          decoration: BoxDecoration(
            border: Border.all(
              color: ArDriveTheme.of(context)
                  .themeData
                  .colors
                  .themeOverlayBackground,
            ),
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ArDriveIcons.iconUploadFiles(
                size: 64,
              ),
              const SizedBox(
                width: 16,
              ),
              Text(
                appLocalizationsOf(context).uploadFiles,
                style: ArDriveTypography.headline.headline2Bold(),
              ),
            ],
          ),
        ),
      );
}
