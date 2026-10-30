import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/locked_drives/domain/drive_password_info.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:collection/collection.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/drive_signature_record_builder.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'private_drive_migration_event.dart';
part 'private_drive_migration_state.dart';

class PrivateDriveMigrationBloc
    extends Bloc<PrivateDriveMigrationEvent, PrivateDriveMigrationState> {
  StreamSubscription? _drivesSubscription;

  final DrivesCubit drivesCubit;
  final DriveDao driveDao;
  final ArDriveAuth ardriveAuth;
  final ArDriveCrypto crypto;
  final TurboUploadService turboUploadService;
  final ArweaveService arweave;
  final DriveUnlocker driveUnlocker;

  /// Builds each record, and refuses to build one it can't prove. See
  /// [DriveSignatureRecordBuilder].
  final DriveSignatureRecordBuilder recordBuilder;

  /// Posts a record. Injectable so tests can watch what would be posted.
  final Future<void> Function(DataItem dataItem, Wallet wallet) _postRecord;

  /// Whether signing asks the user each time (Wander). Such a wallet is
  /// never asked just to decide whether to show the banner.
  final bool Function(Wallet wallet) _isPromptingWallet;

  /// Drives already checked and found unprovable with the sign-in password,
  /// so a wallet that signs locally isn't asked again on every list refresh.
  final Set<String> _unprovable = {};

  List<Drive> drivesRequiringMigration = [];
  Set<Drive> completedMigration = {};

  PrivateDriveMigrationBloc({
    required this.drivesCubit,
    required this.driveDao,
    required this.ardriveAuth,
    required this.crypto,
    required this.turboUploadService,
    required this.arweave,
    required this.driveUnlocker,
    DriveSignatureRecordBuilder? recordBuilder,
    Future<void> Function(DataItem dataItem, Wallet wallet)? postRecord,
    bool Function(Wallet wallet)? isPromptingWallet,
  })  : _isPromptingWallet =
            isPromptingWallet ?? ((wallet) => wallet is ArConnectWallet),
        recordBuilder = recordBuilder ??
            DriveSignatureRecordBuilder(
              crypto: crypto,
              arweave: arweave,
              unlocker: driveUnlocker,
            ),
        _postRecord = postRecord ??
            ((dataItem, wallet) =>
                _post(turboUploadService, arweave, dataItem, wallet)),
        super(PrivateDriveMigrationHidden()) {
    _drivesSubscription = drivesCubit.stream.listen((state) {
      if (state is DrivesLoadSuccess) {
        add(const PrivateDriveMigrationCheck());
      }
    });

    on<PrivateDriveMigrationCloseEvent>((event, emit) {
      emit(PrivateDriveMigrationHidden());
    });

    on<PrivateDriveMigrationCheck>(_checkDrivesForMigration);

    on<PrivateDriveMigrationStartEvent>(_performDriveMigration);

    on<PrivateDriveMigrationPasswordEntered>((event, emit) {
      final reply = _passwordReply;
      _passwordReply = null;
      reply?.complete(event.password);
    });
    // do initial check on startup
    add(const PrivateDriveMigrationCheck());
  }

  /// Lists the v1 drives that need migrating and can be migrated safely.
  ///
  /// A drive is listed only when this session knows a password proven to make
  /// its key: one proven on it this session (sign-in or unlock), or, for a
  /// wallet that signs without asking, the sign-in password checked here. A
  /// drive opened from a key stored on this device or attached by key has no
  /// proven password, and the record builder would refuse it - so offering it
  /// made a banner that came back on every load, asked the wallet twice per
  /// click and ended in an error. It is offered once the user unlocks it with
  /// its password.
  Future<void> _checkDrivesForMigration(PrivateDriveMigrationCheck event,
      Emitter<PrivateDriveMigrationState> emit) async {
    final done = Completer<void>();
    _lastCheck = done.future;
    try {
      await _check(emit);
    } finally {
      done.complete();
    }
  }

  /// The check in flight, which a migration started meanwhile waits for: it
  /// decides which drives are on the list.
  Future<void>? _lastCheck;

  /// Which check is the newest. Two can overlap - the drive list refreshes
  /// while one runs - and the older one finishing last must not overwrite
  /// the newer's answer.
  int _checkGeneration = 0;

  Future<void> _check(Emitter<PrivateDriveMigrationState> emit) async {
    final generation = ++_checkGeneration;
    if (drivesCubit.state is DrivesLoadSuccess) {
      final drives = (drivesCubit.state as DrivesLoadSuccess).userDrives;
      final candidates = drives
          .where((drive) =>
              drive.privacy == 'private' &&
              (drive.signatureType == '1' || drive.signatureType == null) &&
              drive.driveKeyGenerated == true)
          .toList();

      final provable = <Drive>[];
      for (final drive in candidates) {
        if (await _offers(drive)) {
          provable.add(drive);
        }
      }

      if (generation != _checkGeneration) {
        return;
      }

      drivesRequiringMigration = provable;
      completedMigration = {};

      if (drivesRequiringMigration.isNotEmpty) {
        emit(PrivateDriveMigrationVisible());
      } else {
        emit(PrivateDriveMigrationHidden());
      }
    }
  }

  /// Whether [drive] goes on the banner.
  ///
  /// A wallet that signs without asking proves the sign-in password here,
  /// silently. Wander would have to be asked, so it is not: every candidate
  /// drive it can open is offered, and its password is proven when the user
  /// presses Update - the drive's own password asked for if the sign-in one
  /// doesn't make its key, and the drive dropped if neither does.
  Future<bool> _offers(Drive drive) async {
    final session = driveUnlocker.session;

    if (session.isLocked(drive.id)) {
      return false;
    }

    if (session.provenPasswordInfo(drive.id) != null) {
      return true;
    }

    if (_unprovable.contains(drive.id)) {
      return false;
    }

    try {
      if (!(await ardriveAuth.isUserLoggedIn())) {
        return false;
      }

      final user = ardriveAuth.currentUser;

      final currentKey = await driveDao.getDriveKeyFromMemory(drive.id) ??
          await driveDao.getStoredDriveKey(drive.id, user.cipherKey);

      if (currentKey == null) {
        return false;
      }

      if (_isPromptingWallet(user.wallet)) {
        return true;
      }

      final keyBytes = await currentKey.key.extractBytes();
      final v1Signature = await crypto.walletSignatureForDrive(
          user.wallet, drive.id, DriveSignatureType.v1);

      for (final info in drivePasswordInfos(user.password)) {
        final derived = await crypto.driveKeyFromSignature(v1Signature, info,
            generated: true);

        if (const ListEquality<int>()
            .equals(await derived.key.extractBytes(), keyBytes)) {
          session.rememberProvenPasswordInfo(drive.id, info);
          return true;
        }
      }
    } catch (e) {
      logger.w('Could not check whether ${drive.id} can be migrated: $e');
      return false;
    }

    _unprovable.add(drive.id);
    return false;
  }

  Future<void> _performDriveMigration(PrivateDriveMigrationStartEvent event,
      Emitter<PrivateDriveMigrationState> emit) async {
    // stop listening to drivesCubit stream here
    // to ensure no more events are processed while performing migration
    _drivesSubscription?.cancel();
    _drivesSubscription = null;

    await _lastCheck;

    if (!(await ardriveAuth.isUserLoggedIn())) {
      emit(const PrivateDriveMigrationFailed(error: 'User is not logged in'));
      return;
    }

    final user = ardriveAuth.currentUser;
    final wallet = user.wallet;

    /// Drives left as they were because their record couldn't be proven.
    var notMigrated = 0;

    try {
      for (final drive in drivesRequiringMigration) {
        if (completedMigration.contains(drive)) {
          continue;
        }
        emit(PrivateDriveMigrationInProgress(
          inProgressDrive: drive,
        ));

        var record = await _provenRecord(drive, user.cipherKey, user);

        // The sign-in password doesn't make this drive's key: ask for the
        // drive's own, until one does or the user skips it.
        var wrong = false;
        while (record == null &&
            recordBuilder.lastRefusal ==
                DriveSignatureRecordRefusal.unknownPassword) {
          final reply = Completer<String?>();
          _passwordReply = reply;
          emit(PrivateDriveMigrationNeedsPassword(
              drive: drive, wrongPassword: wrong));
          final password = await reply.future;

          if (password == null || password.isEmpty) {
            break;
          }

          emit(PrivateDriveMigrationInProgress(inProgressDrive: drive));
          record = await _provenRecord(drive, user.cipherKey, user,
              password: password);
          wrong = true;
        }

        if (record == null) {
          notMigrated++;
          continue;
        }

        final owner = await wallet.getOwner();
        final appInfo = AppInfoServices().appInfo;
        final driveSignatureDataItem =
            await record.asPreparedDataItem(owner: owner, appInfo: appInfo);

        await driveSignatureDataItem.sign(ArweaveSigner(wallet));

        await _postRecord(driveSignatureDataItem, wallet);

        completedMigration.add(drive);

        // updated persisted and in-memory drive key values
        await driveDao.updateDrive(drive.toCompanion(true).copyWith(
              driveKeyGenerated: const Value(false),
            ));

        final driveKey = await driveDao.getDriveKeyFromMemory(drive.id) ??
            await driveDao.getStoredDriveKey(drive.id, user.cipherKey);

        if (driveKey != null) {
          await driveDao.putDriveKeyInMemory(
            driveID: drive.id,
            driveKey: DriveKey(driveKey.key, false),
          );
        }
      }

      if (notMigrated > 0) {
        emit(const PrivateDriveMigrationFailed(
            error: 'Error updating drive, please try again.'));
        return;
      }

      emit(PrivateDriveMigrationComplete());
    } catch (e) {
      emit(const PrivateDriveMigrationFailed(
          error: 'Error updating drive, please try again.'));
    }
    // emit(PrivateDriveMigrationHidden());
  }

  /// [drive]'s record, or null when it must not be migrated.
  ///
  /// Never a locked drive, never one without a key on this device, and never
  /// with a password that isn't proven to make that drive's key. The record
  /// itself is proven by [DriveSignatureRecordBuilder].
  /// Answers the [PrivateDriveMigrationNeedsPassword] in progress.
  Completer<String?>? _passwordReply;

  Future<DriveSignatureEntity?> _provenRecord(
    Drive drive,
    SecretKey profileKey,
    User user, {
    String? password,
  }) async {
    // A refusal belongs to the drive it was made for: without this, a drive
    // that returns early below would be read with the previous drive's.
    recordBuilder.lastRefusal = null;

    if (driveUnlocker.session.isLocked(drive.id)) {
      return null;
    }

    final currentKey = await driveDao.getDriveKeyFromMemory(drive.id) ??
        await driveDao.getStoredDriveKey(drive.id, profileKey);

    if (currentKey == null) {
      return null;
    }

    final proven = driveUnlocker.session.provenPasswordInfo(drive.id);

    return recordBuilder.build(
      wallet: user.wallet,
      driveId: drive.id,
      currentKey: currentKey,
      passwordInfos: password != null
          ? drivePasswordInfos(password)
          : [
              if (proven != null) proven,
              ...drivePasswordInfos(user.password),
            ],
    );
  }

  /// Via Turbo (free/credits) when enabled, otherwise directly to the network
  /// (pays AR from the wallet) - the same config-based branch every other ArFS
  /// metadata op uses.
  static Future<void> _post(
    TurboUploadService turboUploadService,
    ArweaveService arweave,
    DataItem dataItem,
    Wallet wallet,
  ) async {
    if (turboUploadService.useTurboUpload) {
      await turboUploadService.postDataItem(
        dataItem: dataItem,
        wallet: wallet,
      );
    } else {
      final tx = await arweave.prepareDataBundleTx(
        await DataBundle.fromDataItems(
          items: [dataItem],
        ),
        wallet,
      );
      await arweave.postTx(tx);
    }
  }

  @override
  Future<void> close() {
    _passwordReply?.complete(null);
    _passwordReply = null;
    _drivesSubscription?.cancel();
    return super.close();
  }
}
