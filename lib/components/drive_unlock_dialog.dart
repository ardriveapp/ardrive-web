import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToUnlockDrive(
  BuildContext context, {
  required Drive drive,
}) {
  return showArDriveDialog(
    context,
    content: BlocProvider(
      create: (context) => DriveUnlockCubit(
        drive: drive,
        profileCubit: context.read<ProfileCubit>(),
        driveDao: context.read<DriveDao>(),
        arweave: context.read<ArweaveService>(),
        auth: context.read<ArDriveAuth>(),
        syncCubit: context.read<SyncCubit>(),
        drivesCubit: context.read<DrivesCubit>(),
      ),
      child: const DriveUnlockDialog(),
    ),
  );
}

class DriveUnlockDialog extends StatefulWidget {
  const DriveUnlockDialog({super.key});

  @override
  State<DriveUnlockDialog> createState() => _DriveUnlockDialogState();
}

class _DriveUnlockDialogState extends State<DriveUnlockDialog> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordValid = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DriveUnlockCubit, DriveUnlockState>(
      listener: (context, state) {
        if (state is DriveUnlockSuccess) {
          Navigator.of(context).pop();
          // Navigate to the unlocked drive
          context.read<DrivesCubit>().selectDrive(state.driveId);
        }
      },
      builder: (context, state) {
        final cubit = context.read<DriveUnlockCubit>();
        
        return ArDriveStandardModalNew(
          title: 'Unlock Private Drive',
          content: SizedBox(
            width: kMediumDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter the password to unlock this drive',
                  style: ArDriveTypographyNew.of(context).paragraphNormal(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Drive ID: ${cubit._drive.id}',
                  style: ArDriveTypographyNew.of(context).paragraphSmall(
                    color: ArDriveTheme.of(context).themeData.colorTokens.textLow,
                  ),
                ),
                const SizedBox(height: 16),
                ArDriveTextFieldNew(
                  controller: _passwordController,
                  autofocus: true,
                  obscureText: true,
                  hintText: appLocalizationsOf(context).password,
                  onFieldSubmitted: (value) {
                    if (_isPasswordValid && state is! DriveUnlockInProgress) {
                      cubit.submitWithPassword(value);
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      setState(() => _isPasswordValid = false);
                      return 'Password is required';
                    }
                    setState(() => _isPasswordValid = true);
                    return null;
                  },
                ),
                if (state is DriveUnlockFailure) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.errorMessage ?? 'Incorrect password. Please try again.',
                    style: ArDriveTypographyNew.of(context).paragraphNormal(
                      color: ArDriveTheme.of(context).themeData.colorTokens.textRed,
                    ),
                  ),
                ],
                if (state is DriveUnlockInProgress) ...[
                  const SizedBox(height: 16),
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Unlocking drive and loading contents...',
                      style: ArDriveTypographyNew.of(context).paragraphNormal(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            ModalAction(
              action: () => Navigator.of(context).pop(),
              title: appLocalizationsOf(context).cancelEmphasized,
            ),
            ModalAction(
              action: () => cubit.submitWithPassword(_passwordController.text),
              title: 'UNLOCK',
              isEnable: _isPasswordValid && state is! DriveUnlockInProgress,
            ),
          ],
        );
      },
    );
  }
}

// Simple cubit for drive unlock
class DriveUnlockCubit extends Cubit<DriveUnlockState> {
  final Drive _drive;
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final ArDriveAuth _auth;
  final SyncCubit _syncCubit;
  final DrivesCubit _drivesCubit;

  DriveUnlockCubit({
    required Drive drive,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ArweaveService arweave,
    required ArDriveAuth auth,
    required SyncCubit syncCubit,
    required DrivesCubit drivesCubit,
  })  : _drive = drive,
        _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        _auth = auth,
        _syncCubit = syncCubit,
        _drivesCubit = drivesCubit,
        super(DriveUnlockInitial());

  Future<void> submitWithPassword(String password) async {
    if (password.isEmpty) return;

    emit(DriveUnlockInProgress());

    try {
      final profile = _profileCubit.state as ProfileLoggedIn;

      // Try to decrypt the drive with the provided password
      final driveKey = await _arweave.tryDecryptDrive(
        driveId: _drive.id,
        wallet: profile.user.wallet,
        password: password,
      );

      if (driveKey != null) {
        // Store the drive key in memory
        await _driveDao.putDriveKeyInMemory(
          driveID: _drive.id,
          driveKey: driveKey,
        );

        // Fetch and decrypt the drive entity to get the real data
        final driveTxs = await _arweave.getUniqueUserDriveEntityTxs(
          await profile.user.wallet.getAddress(),
        );
        
        final driveTx = driveTxs.firstWhere(
          (tx) => tx.getTag(EntityTag.driveId) == _drive.id,
          orElse: () => throw Exception('Drive transaction not found'),
        );

        // Get the drive entity data
        final driveResponse = await _arweave.client.api.getSandboxedTx(driveTx.id);
        final driveEntity = await DriveEntity.fromTransaction(
          driveTx,
          ArDriveCrypto(),
          driveResponse.bodyBytes,
          driveKey.key,
        );

        // Update the drive in the database with the real decrypted data
        await _driveDao.updateUserDrives(
          {driveEntity: driveKey},
          profile.user.cipherKey,
        );

        // Trigger a sync to load all the drive's contents
        _syncCubit.startSync();

        // Refresh drives list to trigger migration check
        await _drivesCubit.refreshDrives();

        emit(DriveUnlockSuccess(driveId: _drive.id));
      } else {
        emit(DriveUnlockFailure(errorMessage: 'Incorrect password. Please try again.'));
      }
    } catch (e) {
      // Differentiate between different error types
      String errorMessage;
      if (e.toString().contains('network') || e.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your connection and try again.';
      } else if (e.toString().contains('Drive not found')) {
        errorMessage = 'Drive not found. It may have been deleted or you may not have access.';
      } else {
        errorMessage = 'Failed to unlock drive. Please try again.';
      }
      
      emit(DriveUnlockFailure(errorMessage: errorMessage));
    }
  }
}

// States
abstract class DriveUnlockState {}

class DriveUnlockInitial extends DriveUnlockState {}

class DriveUnlockInProgress extends DriveUnlockState {}

class DriveUnlockSuccess extends DriveUnlockState {
  final String driveId;
  
  DriveUnlockSuccess({required this.driveId});
}

class DriveUnlockFailure extends DriveUnlockState {
  final String? errorMessage;
  
  DriveUnlockFailure({this.errorMessage});
}