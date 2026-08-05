import 'dart:async';
import 'dart:math';

import 'package:ardrive/pages/shared_file/shared_file_identity.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// RESOLVING - the file is being looked up.
///
/// A v2 link already knows the name and the size, so the skeleton is only ever
/// a skeleton where the link was silent. The recipient sees what they are
/// waiting for while they wait for it.
class SharedFileResolvingView extends StatelessWidget {
  const SharedFileResolvingView({super.key, this.payload});

  final SharedFileLinkPayload? payload;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final payload = this.payload;
    final detailsAreHidden = payload?.detailsAreHidden ?? false;
    final showEmbeddedDetails = payload != null && !detailsAreHidden;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SharedFileIdentity(
          name: showEmbeddedDetails ? payload.name : null,
          size: showEmbeddedDetails ? payload.size : null,
          contentType: showEmbeddedDetails ? payload.contentType : null,
          isPrivate: payload?.cipher != null,
          isLoading: true,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                appLocalizationsOf(context).sharedFileLoadingDetails,
                style: ArDriveTypography.body.captionRegular(
                  color: colors.themeFgSubtle,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// NOT_FOUND - nothing answered for this file.
///
/// Three situations wear the same 404, and the recipient deserves to be told
/// which one they are in:
///
/// * a file uploaded moments ago that has not propagated - the resolver is
///   already retrying, and this card counts the wait down;
/// * a file that has been retried to the end of the budget - it says so, and
///   offers a manual retry;
/// * a file id nobody ever wrote - the plain truth, as today.
///
/// The countdown is a *display* of the resolver's own backoff. This widget
/// never fires a retry of its own: `SharedFileCubit` owns the schedule, and a
/// second timer racing it would double every request.
class SharedFileNotFoundView extends StatefulWidget {
  const SharedFileNotFoundView({
    super.key,
    required this.mayStillBePropagating,
    required this.retryAttempt,
    required this.onRetry,
    this.retryDelay = const Duration(seconds: 3),
  });

  /// Whether the resolver is waiting to try again, because the link asserted
  /// that this file exists.
  final bool mayStillBePropagating;

  /// How many automatic attempts the resolver has made. `0` means it never
  /// started - the file id itself is unknown.
  final int retryAttempt;

  /// Runs when the recipient asks for another attempt themselves.
  final VoidCallback onRetry;

  /// The resolver's base delay. It backs off by multiplying this by the attempt
  /// number, and so does the countdown (`SharedFileCubit` line
  /// `_propagationRetryDelay * _propagationAttempts`).
  final Duration retryDelay;

  @override
  State<SharedFileNotFoundView> createState() => _SharedFileNotFoundViewState();
}

class _SharedFileNotFoundViewState extends State<SharedFileNotFoundView> {
  Timer? _timer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void didUpdateWidget(covariant SharedFileNotFoundView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.retryAttempt != widget.retryAttempt ||
        oldWidget.mayStillBePropagating != widget.mayStillBePropagating) {
      _startCountdown();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    if (widget.mayStillBePropagating) {
      return _SharedFileMessage(
        icon: ArDriveIcons.cloudSync(size: 32, color: colors.themeFgSubtle),
        message: _secondsRemaining > 0
            ? appLocalizationsOf(context)
                .sharedFileStillPropagating(_secondsRemaining)
            : appLocalizationsOf(context).sharedFileRetryingNow,
      );
    }

    return _SharedFileMessage(
      icon: ArDriveIcons.fileX(size: 32, color: colors.themeFgSubtle),
      // An attempt was spent, so the file was expected to be there: the honest
      // answer is that we cannot find it *right now*, not that it is not real.
      message: widget.retryAttempt > 0
          ? appLocalizationsOf(context).sharedFileNotFoundOnNetwork
          : appLocalizationsOf(context).specifiedFileDoesNotExist,
      actionLabel: appLocalizationsOf(context).sharedFileRetry,
      onAction: widget.onRetry,
    );
  }

  void _startCountdown() {
    _timer?.cancel();

    if (!widget.mayStillBePropagating) {
      _secondsRemaining = 0;

      return;
    }

    // Assigned directly rather than through setState: this runs from initState
    // and didUpdateWidget, and a build follows both.
    _secondsRemaining =
        widget.retryDelay.inSeconds * max(widget.retryAttempt, 1);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsRemaining <= 0) {
        timer.cancel();

        return;
      }

      setState(() => _secondsRemaining -= 1);
    });
  }
}

/// ERROR_NETWORK - the gateways are not answering.
class SharedFileNetworkErrorView extends StatelessWidget {
  const SharedFileNetworkErrorView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return _SharedFileMessage(
      icon: ArDriveIcons.triangle(size: 32, color: colors.themeFgSubtle),
      message: appLocalizationsOf(context).sharedFileNetworkTrouble,
      actionLabel: appLocalizationsOf(context).sharedFileRetry,
      onAction: onRetry,
    );
  }
}

/// ERROR_LINK - the link itself did not survive the trip.
///
/// There is nothing to retry: only the sender can fix a link that arrived in
/// pieces, so the page says exactly that and stops.
class SharedFileLinkErrorView extends StatelessWidget {
  const SharedFileLinkErrorView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return _SharedFileMessage(
      icon: ArDriveIcons.fileX(size: 32, color: colors.themeFgSubtle),
      message: appLocalizationsOf(context).sharedFileLinkIncomplete,
    );
  }
}

class _SharedFileMessage extends StatelessWidget {
  const _SharedFileMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final Widget icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final actionLabel = this.actionLabel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(child: icon),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: ArDriveTypography.body.bodyRegular(
            color: colors.themeFgDefault,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 24),
          ArDriveButton(
            maxWidth: double.infinity,
            onPressed: onAction,
            text: actionLabel,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
