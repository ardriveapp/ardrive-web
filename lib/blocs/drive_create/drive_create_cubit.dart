import 'package:ardrive/authentication/password/new_password.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_entity.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/locked_drives/data/sign_in_password_proof_store.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'drive_create_state.dart';

/// What a new private drive asks of the user for its key. See
/// [DriveCreateCubit.drivePasswordAsk].
enum DrivePasswordAsk {
  /// Set the drive password: the user has none yet, and no private drive.
  set,

  /// Enter the drive password they have, checked by opening one of their
  /// private drives.
  enter,
}

class DriveCreateCubit extends Cubit<DriveCreateState> {
  final form = FormGroup({
    'privacy': FormControl<String>(
        value: DrivePrivacyTag.private, validators: [Validators.required]),
  });

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final DrivesCubit _drivesCubit;
  final DriveUnlocker? _driveUnlocker;
  final SignInPasswordProofStore _proofStore;
  final DrivePrivacy privacy;

  DriveCreateCubit({
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required DrivesCubit drivesCubit,
    this.privacy = DrivePrivacy.private,

    /// Where it learns whether the sign-in password was proven, and checks a
    /// drive password. The first drive of a new account passes none: that
    /// account has just chosen its password, and has no private drive for it
    /// to have failed on.
    DriveUnlocker? driveUnlocker,
    SignInPasswordProofStore? proofStore,
  })  : _driveUnlocker = driveUnlocker,
        _proofStore = proofStore ?? SignInPasswordProofStore(),
        _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _drivesCubit = drivesCubit,
        super(DriveCreateInitial(privacy: privacy)) {
    form.control('privacy').value = privacy.name;
  }

  /// Whether a new private drive needs a drive password from the user, and
  /// which kind. Null when the session already has the password a new private
  /// drive's key is made from.
  ///
  /// One drive password protects all of a user's private drives (the 3.0
  /// password design).
  /// - A keyfile, recovery phrase or generated account signed in with it, so
  ///   nothing is asked, unless that password opened none of their private
  ///   drives at sign-in and they continued anyway: it may be a typo, so the
  ///   drive password is asked for and checked by opening one of their
  ///   drives ([DrivePasswordAsk.enter]).
  /// - An account that signed in with a browser wallet (Wander, Phantom,
  ///   Solflare, a new MetaMask account, or any MetaMask account after a
  ///   reload) typed no password. With no private drive yet it sets one
  ///   ([DrivePasswordAsk.set], under the new-account rules). With private
  ///   drives it enters theirs, checked the same way.
  ///
  /// Once set or checked, the rest of the session uses it: never a choice
  /// per drive.
  DrivePasswordAsk? get drivePasswordAsk {
    final profile = _profileCubit.state;
    final session = _driveUnlocker?.session;

    if (state.privacy != DrivePrivacy.private ||
        profile is! ProfileLoggedIn ||
        session == null) {
      return null;
    }

    final address = profile.user.walletAddress;
    if (session.newDrivePassword(address) != null) return null;

    final noSignInPassword = profile.user.password.isEmpty;
    if (!noSignInPassword && session.signInPasswordProven(address) != false) {
      return null;
    }

    return noSignInPassword && !_hasPrivateDrives(address)
        ? DrivePasswordAsk.set
        : DrivePasswordAsk.enter;
  }

  /// Whether a new private drive needs a drive password typed or set; see
  /// [drivePasswordAsk].
  bool get needsDrivePassword => drivePasswordAsk != null;

  /// Whether [address] has a private drive: one listed, or one locked, or
  /// one the network check found ([confirmDrivePasswordAsk]). A drive list
  /// that hasn't loaded counts as having one, so a password is checked rather
  /// than set over drives not seen yet.
  bool _hasPrivateDrives(String address) {
    if (_privateDrivesOnChain == true) return true;
    final drives = _drivesCubit.state;
    if (drives is! DrivesLoadSuccess) return true;
    return drives.userDrives.any((d) => d.isPrivate) ||
        drives.lockedDrives.isNotEmpty ||
        (_driveUnlocker?.session.currentLockedDrives
                .any((drive) => drive.ownerAddress == address) ??
            false);
  }

  /// What Arweave said about the user's private drives: true when it has
  /// one, false when it has none, null until asked or when it couldn't
  /// answer.
  bool? _privateDrivesOnChain;

  /// [drivePasswordAsk], checked against Arweave before a drive password is
  /// *set*: a local list can be empty because the drives haven't synced or
  /// discovery failed, and a password set then would split the user's
  /// drives across two passwords. Arweave having a private drive of theirs,
  /// or not answering, makes it [DrivePasswordAsk.enter].
  Future<DrivePasswordAsk?> confirmDrivePasswordAsk() async {
    final ask = drivePasswordAsk;
    if (ask != DrivePasswordAsk.set) return ask;

    final profile = _profileCubit.state as ProfileLoggedIn;
    try {
      final first = await _arweave.getFirstPrivateDriveTx(
        profile.user.wallet,
        maxRetries: unlockMaxRetries,
      );
      _privateDrivesOnChain = first != null;
    } catch (e) {
      logger.w('Could not check for private drives on Arweave: $e');
      // Unknown: never set a password over drives that may exist.
      _privateDrivesOnChain = true;
    }
    return drivePasswordAsk;
  }

  /// The password a new private drive's key is made from: the drive password
  /// set or checked this session when there is one and the sign-in password
  /// is absent or unproven, otherwise the sign-in password.
  String _keyPassword(ProfileLoggedIn profile) {
    final address = profile.user.walletAddress;
    final session = _driveUnlocker?.session;
    final drivePassword = session?.newDrivePassword(address);

    if (drivePassword != null &&
        (profile.user.password.isEmpty ||
            session!.signInPasswordProven(address) == false)) {
      return drivePassword;
    }
    return profile.user.password;
  }

  /// The user's private drives with rows, oldest first: what a drive password
  /// is checked on when none is locked.
  List<String> get _knownPrivateDriveIds {
    final drives = _drivesCubit.state;
    if (drives is! DrivesLoadSuccess) return const [];
    final private = drives.userDrives.where((d) => d.isPrivate).toList()
      ..sort((a, b) => a.dateCreated.compareTo(b.dateCreated));
    return [for (final drive in private) drive.id];
  }

  void onPrivacyChanged() {
    final privacy = form.control('privacy').value == DrivePrivacy.private.name
        ? DrivePrivacy.private
        : DrivePrivacy.public;
    emit(state.copyWith(privacy: privacy));
  }

  /// Creates the drive.
  ///
  /// - [DrivePasswordAsk.enter]: [drivePassword] is the user's drive
  ///   password. It must open one of their existing private drives first, or
  ///   nothing is created.
  /// - [DrivePasswordAsk.set]: [newDrivePassword] is the drive password just
  ///   set. It must meet the new-account rules; the breach check is the
  ///   dialog's. The rest of the session uses it.
  Future<void> submit(
    String driveName, {
    String? drivePassword,
    String? newDrivePassword,
  }) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    final ask = drivePasswordAsk;

    if (ask == DrivePasswordAsk.set) {
      if (_privateDrivesOnChain != false) {
        throw StateError('Check for private drives on Arweave first: '
            'confirmDrivePasswordAsk');
      }
      if (newDrivePassword == null ||
          assessNewPassword(newDrivePassword) != PasswordStrength.strong) {
        throw ArgumentError(
            'A strong new drive password is needed', 'newDrivePassword');
      }
      _driveUnlocker!.session
          .setNewDrivePassword(profile.user.walletAddress, newDrivePassword);
    } else if (ask == DrivePasswordAsk.enter) {
      if (drivePassword == null || drivePassword.isEmpty) {
        throw ArgumentError('A drive password is needed', 'drivePassword');
      }

      final failure = await _driveUnlocker!.verifyDrivePassword(
        wallet: profile.user.wallet,
        profileKey: profile.user.cipherKey,
        password: drivePassword,
        knownPrivateDriveIds: _knownPrivateDriveIds,
      );

      if (failure != null) {
        emit(failure == DriveUnlockFailure.walletDeclined
            ? DriveCreateInitial(privacy: state.privacy)
            : DriveCreateDrivePasswordRejected(
                privacy: state.privacy,
                reason: failure,
              ));
        return;
      }

      // Checked: it opened one of their drives, which stays unlocked. The
      // rest of this session uses it too. If it is the sign-in password after
      // all, that is now proven, here and on this device.
      final address = profile.user.walletAddress;
      _driveUnlocker.session
        ..setNewDrivePassword(address, drivePassword)
        ..rememberProvenDrivePassword(address, drivePassword);
      if (drivePassword == profile.user.password) {
        _driveUnlocker.session.setSignInPasswordProven(address, true);
        await _proofStore.clear(address);
      }
    }
    try {
      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(DriveCreateWalletMismatch(privacy: state.privacy));
        return;
      }
    } on ArConnectUnavailableException catch (e) {
      // Wander couldn't be reached and the person chose Cancel. Nothing was
      // written: the form stays, to try again or close.
      logger.w('Could not check the wallet before creating a drive: $e');
      return;
    }

    final minimumWalletBalance = BigInt.from(10000000);
    if (profile.user.walletBalance <= minimumWalletBalance &&
        !_turboUploadService.useTurboUpload) {
      emit(DriveCreateZeroBalance(privacy: state.privacy));
      return;
    }

    emit(DriveCreateInProgress(privacy: state.privacy));

    String? driveId;

    try {
      final String drivePrivacy = form.control('privacy').value;
      final walletAddress = await profile.user.wallet.getAddress();

      final createRes = await _driveDao.createDrive(
        name: driveName,
        ownerAddress: walletAddress,
        privacy: drivePrivacy,
        wallet: profile.user.wallet,
        password: _keyPassword(profile),
        profileKey: profile.user.cipherKey,
        signatureType: drivePrivacy == DrivePrivacyTag.private ? '2' : null,
      );
      driveId = createRes.driveId;

      final drive = DriveEntity(
        id: createRes.driveId,
        name: driveName,
        rootFolderId: createRes.rootFolderId,
        privacy: drivePrivacy,
        authMode: drivePrivacy == DrivePrivacyTag.private
            ? DriveAuthModeTag.password
            : null,
        signatureType: drivePrivacy == DrivePrivacyTag.private
            ? DriveSignatureType.v2
            : null,
      );

      final driveDataItem = await _arweave.prepareEntityDataItem(
        drive,
        profile.user.wallet,
        key: createRes.driveKey,
      );

      final rootFolderEntity = FolderEntity(
        id: drive.rootFolderId,
        driveId: drive.id,
        name: driveName,
      );

      final rootFolderDataItem = await _arweave.prepareEntityDataItem(
        rootFolderEntity,
        profile.user.wallet,
        key: createRes.driveKey,
      );

      final signer = ArweaveSigner(profile.user.wallet);

      await rootFolderDataItem.sign(signer);
      await driveDataItem.sign(signer);
      late TransactionBase createTx;
      if (_turboUploadService.useTurboUpload) {
        createTx = await _arweave.prepareBundledDataItem(
          await DataBundle.fromDataItems(
            items: [driveDataItem, rootFolderDataItem],
          ),
          profile.user.wallet,
        );
        await _turboUploadService.postDataItem(
          dataItem: createTx as DataItem,
          wallet: profile.user.wallet,
        );
      } else {
        createTx = await _arweave.prepareDataBundleTx(
          await DataBundle.fromDataItems(
            items: [driveDataItem, rootFolderDataItem],
          ),
          profile.user.wallet,
        );
        await _arweave.postTx(createTx as Transaction);
      }

      rootFolderEntity.txId = rootFolderDataItem.id;
      await _driveDao.insertFolderRevision(rootFolderEntity.toRevisionCompanion(
          performedAction: RevisionAction.create));

      // Update drive with bundledIn
      // Creates a drive revision immediately after creation
      // so there is no more pending state in the info panel when waiting for sync to
      // pick up the drive

      drive
        ..ownerAddress = walletAddress
        ..bundledIn = createTx.id
        ..txId = driveDataItem.id;

      await _driveDao.insertDriveRevision(
          drive.toRevisionCompanion(performedAction: RevisionAction.create));
      _drivesCubit.selectDrive(drive.id!);

      emit(DriveCreateSuccess(privacy: state.privacy));
    } catch (err) {
      // Clean up new drive from DB if necessary...
      if (driveId != null) {
        try {
          await _driveDao.detachDrive(driveId);
        } catch (e) {
          logger.e('Failed to detach drive with ID $driveId', e);
        }
      }
      addError(err);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(DriveCreateFailure(
      privacy: state.privacy,
      isPaymentError: isTurboPaymentError(error),
      walletCantMakeDriveKeys: error is WalletCantMakeDriveKeysException,
    ));
    super.onError(error, stackTrace);

    logger.e('Failed to create drive', error, stackTrace);
  }
}
