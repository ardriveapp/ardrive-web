import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_uploader.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';

/// Chooses what sits behind the confirm button, and is the rail that decides
/// whether publishing is possible at all.
///
/// `AppConfig.enableDriveStatePublishing` gates the New menu item too, but a
/// menu gate is a gate on one caller. This is the gate on the capability: with
/// [publishingEnabled] false, [whenEnabled] is **not called**, so no object
/// that knows how to reach a network is constructed, let alone reached. That
/// is what `docs/drive-state/DECISIONS.md` D8 asks for — "the way to hold a
/// rail is to have no code that could cross it".
DriveStateUploader driveStateUploaderFor({
  required bool publishingEnabled,
  required DriveStateUploader Function() whenEnabled,
}) =>
    publishingEnabled ? whenEnabled() : const UnwiredDriveStateUploader();

/// Puts a prepared artifact on Arweave, over whichever transport the user
/// paid for.
///
/// Reached from exactly one place: [DriveStateCreationCubit.publish], itself
/// reached from exactly one place, the confirm button. Nothing constructs
/// this class on a timer, during preparation, or at start-up, and the flow
/// that does construct it is behind `AppConfig.enableDriveStatePublishing`
/// (`DECISIONS.md` D8; the reasoning is on [DriveStateUploader]).
///
/// ## Both transports, neither required
///
/// `docs/DRIVE_STATE_ARTIFACT.md` §4.4 is a requirement, not a preference: an
/// artifact must be publishable as a plain L1 transaction so the format
/// outlives Turbo, and as a bundled data item so it is cheap while Turbo is
/// there. Both branches exist here and neither is a fallback for the other —
/// the user chose, and this class does what they chose.
///
/// ## Why it mirrors `create_snapshot_cubit.dart`
///
/// That cubit is the closest analogue in the app and it has already been
/// taught the awkward parts of this path. Two are load-bearing:
///
/// - **Prepare without signing, sign afterwards.** `skipSignature: true` on
///   both prepare calls, then an explicit `sign`. It is what lets signing be
///   retried on its own when the wallet is a browser extension.
/// - **ArConnect cannot sign while the tab is in the background.** The call
///   throws, and the fix is to wait for the tab to be focused and try the
///   same step again rather than to fail the publish. A real bug class: a
///   user who switches tabs during a signature prompt otherwise loses the
///   artifact they just paid to prepare.
///
/// ## What it deliberately does not do
///
/// No row is written to `network_transactions`. A snapshot does that so the
/// Snapshots tab can show a pending status; an artifact has no such surface,
/// and its readers discover it by GraphQL rather than from this database. A
/// speculative row here would be an orphan the export lane has to reason
/// about for no benefit.
class ArweaveDriveStateUploader implements DriveStateUploader {
  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final ProfileCubit _profileCubit;
  final TabVisibilitySingleton _tabVisibility;

  ArweaveDriveStateUploader({
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required ProfileCubit profileCubit,
    required TabVisibilitySingleton tabVisibility,
  })  : _arweave = arweave,
        _turboUploadService = turboUploadService,
        _profileCubit = profileCubit,
        _tabVisibility = tabVisibility;

  @override
  Future<DriveStateUploadResult> publish(
    PreparedDriveStateArtifact artifact, {
    required UploadMethod method,
  }) async {
    final profile = _profileCubit.state;
    if (profile is! ProfileLoggedIn) {
      return const DriveStateUploadResult.failed(
        'You are no longer logged in. Nothing was uploaded and nothing was '
        'spent.',
      );
    }

    // The wallet may have been switched in the extension between preparing
    // the artifact and confirming it. The artifact is signed with the wallet
    // that prepared it, so publishing under a different one would pay for an
    // artifact whose signature no importer accepts.
    if (await _profileCubit.logoutIfWalletMismatch()) {
      logger.w('[drive-state] refusing to publish: wallet mismatch');
      return const DriveStateUploadResult.failed(
        'Your wallet changed while this artifact was being prepared. Nothing '
        'was uploaded and nothing was spent.',
      );
    }

    final wallet = profile.user.wallet;
    final isArConnectProfile = await _profileCubit.isCurrentProfileArConnect();
    final useTurbo = method == UploadMethod.turbo;

    try {
      if (useTurbo) {
        final dataItem = await _prepareDataItem(
          artifact,
          wallet,
          isArConnectProfile,
        );
        await _signDataItem(dataItem, wallet, isArConnectProfile);

        logger.i('[drive-state] posting artifact ${dataItem.id} to Turbo');
        await _turboUploadService.postDataItem(
          dataItem: dataItem,
          wallet: wallet,
        );

        return DriveStateUploadResult.published(dataItem.id);
      }

      final tx = await _prepareTx(artifact, wallet, isArConnectProfile);
      await _signTx(tx, wallet, isArConnectProfile);

      logger.i('[drive-state] posting artifact ${tx.id} to Arweave');
      // Chunked, one request at a time, exactly as a snapshot is posted: an
      // artifact runs to tens of MiB, and firing chunks concurrently before
      // the gateway has indexed the data root earns 400s.
      await _arweave.uploadTx(tx, maxConcurrentUploadCount: 1);

      return DriveStateUploadResult.published(tx.id);
    } catch (e, stackTrace) {
      logger.e('[drive-state] publishing an artifact failed', e, stackTrace);

      if (isTurboPaymentError(e)) {
        return const DriveStateUploadResult.failed(
          'Turbo declined the payment for this artifact. Add Credits or '
          'publish with AR, then try again.',
        );
      }

      return const DriveStateUploadResult.failed(
        'The artifact could not be published. If nothing was posted, nothing '
        'was spent — check your drive before trying again.',
      );
    }
  }

  Future<DataItem> _prepareDataItem(
    PreparedDriveStateArtifact artifact,
    Wallet wallet,
    bool isArConnectProfile,
  ) async {
    try {
      return await _arweave.prepareEntityDataItem(
        artifact.entity,
        wallet,
        // Signed below, on its own, so a signature refused because the tab
        // was in the background can be retried without rebuilding the item.
        skipSignature: true,
      );
    } catch (e, stackTrace) {
      return _retryWhenTabRegainsFocus(
        e,
        stackTrace,
        isArConnectProfile,
        'preparing',
        () => _prepareDataItem(artifact, wallet, isArConnectProfile),
      );
    }
  }

  Future<void> _signDataItem(
    DataItem dataItem,
    Wallet wallet,
    bool isArConnectProfile,
  ) async {
    try {
      await dataItem.sign(ArweaveSigner(wallet));
    } catch (e, stackTrace) {
      await _retryWhenTabRegainsFocus(
        e,
        stackTrace,
        isArConnectProfile,
        'signing',
        () async {
          await _signDataItem(dataItem, wallet, isArConnectProfile);
          return dataItem;
        },
      );
    }
  }

  Future<Transaction> _prepareTx(
    PreparedDriveStateArtifact artifact,
    Wallet wallet,
    bool isArConnectProfile,
  ) async {
    try {
      return await _arweave.prepareEntityTx(
        artifact.entity,
        wallet,
        // The body is already sealed by `DriveStateEnvelopeCodec`; handing a
        // key here would ask the entity to encrypt what is already
        // ciphertext, and `DriveStateEntity` throws rather than allow it.
        null,
        skipSignature: true,
      );
    } catch (e, stackTrace) {
      return _retryWhenTabRegainsFocus(
        e,
        stackTrace,
        isArConnectProfile,
        'preparing',
        () => _prepareTx(artifact, wallet, isArConnectProfile),
      );
    }
  }

  Future<void> _signTx(
    Transaction tx,
    Wallet wallet,
    bool isArConnectProfile,
  ) async {
    try {
      await tx.sign(ArweaveSigner(wallet));
    } catch (e, stackTrace) {
      await _retryWhenTabRegainsFocus(
        e,
        stackTrace,
        isArConnectProfile,
        'signing',
        () async {
          await _signTx(tx, wallet, isArConnectProfile);
          return tx;
        },
      );
    }
  }

  /// ArConnect throws when asked to prepare or sign while the tab is not the
  /// focused one. That is a recoverable condition and nothing else here is:
  /// only an ArConnect profile with a genuinely unfocused tab waits, and
  /// every other failure rethrows immediately so the user is told rather than
  /// left watching a spinner that will never end.
  Future<T> _retryWhenTabRegainsFocus<T>(
    Object error,
    StackTrace stackTrace,
    bool isArConnectProfile,
    String step,
    Future<T> Function() retry,
  ) async {
    final isTabFocused = _tabVisibility.isTabFocused();

    if (!isArConnectProfile || isTabFocused) {
      logger.e(
        '[drive-state] $step the artifact transaction failed - '
        'isArConnectProfile: $isArConnectProfile, isTabFocused: $isTabFocused',
        error,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    logger.i(
      '[drive-state] $step the artifact transaction while the tab is not '
      'focused. Waiting for it to come back...',
    );

    late T result;
    await _tabVisibility.onTabGetsFocusedFuture(() async {
      result = await retry();
    });

    return result;
  }
}
