import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_create/first_drive.dart';
import 'package:ardrive/components/list_page/list_page_state_card.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
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

  /// Whether the first drive is being made. It is in the drive list before
  /// it is ready to open, so the list shows this page instead meanwhile.
  static final settingUp = ValueNotifier(false);

  /// Forgets this session's attempts, for tests.
  @visibleForTesting
  static void resetSession() => _FirstDrivePageState._failedThisSession.clear();

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

  /// Wallets whose drive could not be made in this session. Their request is
  /// kept for the next load; trying again now would only repeat the failure.
  static final _failedThisSession = <String>{};

  Future<void> _start() async {
    var running = _running;

    if (running == null) {
      final profile = context.read<ProfileCubit>().state;
      final firstDrive = widget.firstDrive ?? FirstDrive();
      var owed = false;

      if (profile is ProfileLoggedIn &&
          !_failedThisSession.contains(profile.user.walletAddress)) {
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

      FirstDrivePage.settingUp.value = true;
      running = _running = _makeFirstDrive(
        attempt: widget.createFirstDrive(context),
        firstDrive: firstDrive,
        walletAddress: profile.user.walletAddress,
        retryDelays: widget.retryDelays,
      ).whenComplete(() {
        _running = null;
        FirstDrivePage.settingUp.value = false;
      });
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
        // Kept, so the next time the app loads it tries again.
        _failedThisSession.add(walletAddress);
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

/// The same wait as the drives list's "Loading your drives", drawn the same
/// way: they follow each other for a new account.
class _SettingUpFirstDrive extends StatelessWidget {
  const _SettingUpFirstDrive();

  @override
  Widget build(BuildContext context) => ListPageWaiting(
        title: appLocalizationsOf(context).firstDriveSettingUp,
      );
}

/// Makes a private "My files" the way Create new private drive does.
FirstDriveAttempt createMyFiles(BuildContext context) {
  final arweave = context.read<ArweaveService>();
  final turboUploadService = context.read<TurboUploadService>();
  final driveDao = context.read<DriveDao>();
  final profileCubit = context.read<ProfileCubit>();
  final drivesCubit = context.read<DrivesCubit>();

  // With the session, as Create drive has it. A new account has just chosen
  // its password and has no private drive it could have failed to open, so
  // its password is proven and "My files" takes it as every first drive
  // always has; and if it ever weren't, the drive would not be made with it.
  final driveUnlocker = context.read<DriveUnlocker>();

  return () => makeMyFiles(DriveCreateCubit(
        driveUnlocker: driveUnlocker,
        privacy: DrivePrivacy.private,
        arweave: arweave,
        turboUploadService: turboUploadService,
        driveDao: driveDao,
        profileCubit: profileCubit,
        drivesCubit: drivesCubit,
      ));
}

@visibleForTesting
Future<FirstDriveOutcome> makeMyFiles(DriveCreateCubit cubit) async {
  try {
    // Never keyed with an unproven password: no first drive rather than one
    // that opens with something the user may not know.
    if (cubit.needsDrivePassword) {
      return FirstDriveOutcome.failed;
    }

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
