import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_create/first_drive.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/presentation/sync_loading_indicator.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// How an attempt to make the first drive ended.
enum FirstDriveOutcome {
  made,

  /// Turbo would not take it free and there is nothing to pay with. Trying
  /// again won't change that, so the request is dropped.
  needsCredits,

  /// Anything else, such as Turbo or the gateway being unreachable: worth
  /// trying again.
  failed,
}

/// One attempt at making the first drive.
typedef FirstDriveAttempt = Future<FirstDriveOutcome> Function();

/// Reads what making the first drive needs, once, from [context]; the
/// attempts it returns outlive the page that started them.
typedef CreateFirstDrive = FirstDriveAttempt Function(BuildContext context);

/// What a signed-in user with no drives sees. A new account owed its first
/// drive has "My files" made here; making it selects it, which opens it.
/// Everyone else, and a new account whose drive could not be made, sees
/// [noDrives]: Getting started.
class FirstDrivePage extends StatefulWidget {
  const FirstDrivePage({
    super.key,
    required this.noDrives,
    this.firstDrive,
    this.createFirstDrive = createMyFiles,
    this.retryDelays = const [Duration(seconds: 3), Duration(seconds: 10)],
  });

  final WidgetBuilder noDrives;
  final FirstDrive? firstDrive;
  final CreateFirstDrive createFirstDrive;

  /// The waits before each further attempt after one fails.
  final List<Duration> retryDelays;

  @override
  State<FirstDrivePage> createState() => _FirstDrivePageState();
}

enum _Stage { checking, creating, noDrives }

class _FirstDrivePageState extends State<FirstDrivePage> {
  var _stage = _Stage.checking;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// The attempts under way, shared by every page that shows up while they
  /// run: making the drive adds it to the list and a failed try removes it,
  /// which can swap this page for a new one mid-wait.
  static Future<FirstDriveOutcome>? _running;

  Future<void> _start() async {
    var running = _running;

    if (running == null) {
      final profile = context.read<ProfileCubit>().state;
      final firstDrive = widget.firstDrive ?? FirstDrive();
      var owed = false;

      if (profile is ProfileLoggedIn) {
        try {
          owed = await firstDrive.claim(profile.user.walletAddress);
        } catch (e, stackTrace) {
          logger.e('Could not read the first drive request', e, stackTrace);
        }
      }

      if (!mounted) return;

      if (!owed || profile is! ProfileLoggedIn) {
        setState(() => _stage = _Stage.noDrives);
        return;
      }

      running = _running = _makeFirstDrive(
        attempt: widget.createFirstDrive(context),
        firstDrive: firstDrive,
        walletAddress: profile.user.walletAddress,
        retryDelays: widget.retryDelays,
      ).whenComplete(() => _running = null);
    }

    setState(() => _stage = _Stage.creating);

    // On success the new drive is selected, which opens it.
    final outcome = await running;

    if (outcome != FirstDriveOutcome.made && mounted) {
      setState(() => _stage = _Stage.noDrives);
    }
  }

  static Future<FirstDriveOutcome> _makeFirstDrive({
    required FirstDriveAttempt attempt,
    required FirstDrive firstDrive,
    required String walletAddress,
    required List<Duration> retryDelays,
  }) async {
    var outcome = FirstDriveOutcome.failed;
    for (var tries = 0;; tries++) {
      try {
        outcome = await attempt();
      } catch (e, stackTrace) {
        logger.e('Could not make the first drive', e, stackTrace);
        outcome = FirstDriveOutcome.failed;
      }

      if (outcome != FirstDriveOutcome.failed || tries >= retryDelays.length) {
        break;
      }
      await Future<void>.delayed(retryDelays[tries]);
    }

    try {
      if (outcome == FirstDriveOutcome.failed) {
        // Kept, so the next time this account has no drives it tries again.
        await firstDrive.release(walletAddress);
      } else {
        await firstDrive.done();
      }
    } catch (e, stackTrace) {
      logger.e('Could not update the first drive request', e, stackTrace);
    }

    return outcome;
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _Stage.checking => const SizedBox.shrink(),
      _Stage.creating => const _SettingUpFirstDrive(),
      _Stage.noDrives => widget.noDrives(context),
    };
  }
}

class _SettingUpFirstDrive extends StatelessWidget {
  const _SettingUpFirstDrive();

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SyncLoadingIndicator(size: 96),
          const SizedBox(height: ArDriveSpacing.md),
          Text(
            appLocalizationsOf(context).firstDriveSettingUp,
            style: typography.heading5(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Makes a private "My files" the way Create new private drive does.
FirstDriveAttempt createMyFiles(BuildContext context) {
  final arweave = context.read<ArweaveService>();
  final turboUploadService = context.read<TurboUploadService>();
  final driveDao = context.read<DriveDao>();
  final profileCubit = context.read<ProfileCubit>();
  final drivesCubit = context.read<DrivesCubit>();

  return () => _createMyFiles(DriveCreateCubit(
        privacy: DrivePrivacy.private,
        arweave: arweave,
        turboUploadService: turboUploadService,
        driveDao: driveDao,
        profileCubit: profileCubit,
        drivesCubit: drivesCubit,
      ));
}

Future<FirstDriveOutcome> _createMyFiles(DriveCreateCubit cubit) async {
  try {
    // Closed only once submit is done: closing it sooner would make the
    // success emit throw, and the cubit undoes a drive whose creation threw.
    await cubit.submit(firstDriveName);
    return switch (cubit.state) {
      DriveCreateSuccess() => FirstDriveOutcome.made,
      DriveCreateFailure(isPaymentError: true) ||
      DriveCreateZeroBalance() =>
        FirstDriveOutcome.needsCredits,
      _ => FirstDriveOutcome.failed,
    };
  } finally {
    await cubit.close();
  }
}
