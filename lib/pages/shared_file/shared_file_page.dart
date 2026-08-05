import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/pages/shared_file/shared_file_frame.dart';
import 'package:ardrive/pages/shared_file/shared_file_key_session.dart';
import 'package:ardrive/pages/shared_file/shared_file_locked_view.dart';
import 'package:ardrive/pages/shared_file/shared_file_ready_view.dart';
import 'package:ardrive/pages/shared_file/shared_file_status_views.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The recipient's landing page: usually the first and only thing someone ever
/// sees of ArDrive.
///
/// It renders the state machine of `docs/FILE_SHARING_REDESIGN_PLAN.md` §2 -
/// resolving, locked, ready, not found, network trouble - as one column that
/// works the same on a phone as on a monitor. Everything the recipient needs
/// is above the fold; everything a protocol needs is behind a disclosure.
///
/// The page owns three things the individual state views must not: the key
/// text field's controller (so a rejected key survives the reload that
/// rejected it), the "remember while this tab is open" choice, and the
/// tab-scoped key store.
class SharedFilePage extends StatefulWidget {
  const SharedFilePage({super.key, this.keySession});

  /// Injectable so a widget test can observe what the page remembers without a
  /// browser session storage behind it.
  final SharedFileKeySession? keySession;

  @override
  State<SharedFilePage> createState() => _SharedFilePageState();
}

class _SharedFilePageState extends State<SharedFilePage> {
  /// Lives on the page, not on the locked gate: submitting a key tears the
  /// gate down and rebuilds it, and losing the recipient's text at exactly the
  /// moment they were told it was wrong would be the cruelest possible moment
  /// to lose it.
  final TextEditingController _keyController = TextEditingController();

  late final SharedFileKeySession _keySession;
  late final String _fileId;

  bool _rememberKey = false;

  /// Whether the load in progress is a key being checked, as opposed to the
  /// page's first resolution. The locked gate stays on screen for the former.
  bool _isUnlocking = false;

  bool _hasTriedRememberedKey = false;

  /// The key to write to session storage once - and only once - it is known to
  /// work.
  String? _keyToRemember;

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(page: PlausiblePageView.sharedFilePage);

    _keySession = widget.keySession ?? SharedFileKeySession();
    _fileId = context.read<SharedFileCubit>().fileId;
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: BlocConsumer<SharedFileCubit, SharedFileState>(
        listener: _onStateChanged,
        builder: (context, state) => SharedFileFrame(
          child: _buildState(context, state),
        ),
      ),
    );
  }

  void _onStateChanged(BuildContext context, SharedFileState state) {
    if (state is! SharedFileLoadInProgress) {
      _isUnlocking = false;
    }

    if (state is SharedFileKeyInvalid) {
      // A remembered key that stopped working is dropped rather than offered
      // again: it would re-submit itself on every reload and strand the
      // recipient behind an error they never typed.
      _keyToRemember = null;
      unawaited(_keySession.forget(_fileId));

      return;
    }

    if (state is SharedFileLoadSuccess) {
      final rawKey = _keyToRemember;
      _keyToRemember = null;

      if (rawKey != null) {
        unawaited(_keySession.remember(_fileId, rawKey));
      }
    }
  }

  Widget _buildState(BuildContext context, SharedFileState state) {
    if (state is SharedFileLoadSuccess) {
      return SharedFileReadyView(state: state);
    }

    if (state is SharedFileIsPrivate) {
      // Driven from here rather than from the listener because the page can
      // *start* locked - a listener never fires for the state it opens on.
      _tryRememberedKey(context);

      return _buildLocked(context, payload: state.payload);
    }

    if (state is SharedFileKeyInvalid) {
      // A key that never survived the link is a damaged link, not a wrong key:
      // the recipient has to ask the sender for the link again, while a key
      // they type by hand still unlocks the file from this same gate.
      return _buildLocked(
        context,
        payload: state.payload,
        errorMessage: state.linkKeyIsDamaged
            ? appLocalizationsOf(context).sharedFileLinkKeyDamaged
            : appLocalizationsOf(context).sharedFileKeyIncorrect,
      );
    }

    if (state is SharedFileLinkDamaged) {
      // The link named no file at all, so there is nothing to look up and
      // nothing to retry: only the sender can fix this one.
      return const SharedFileLinkErrorView();
    }

    if (state is SharedFileLoadInProgress) {
      if (_isUnlocking) {
        return _buildLocked(context, payload: state.payload, isBusy: true);
      }

      return SharedFileResolvingView(payload: state.payload);
    }

    if (state is SharedFileNotFound) {
      // The resolver owns the retry schedule; this card only shows it. See
      // [SharedFileNotFoundView].
      return SharedFileNotFoundView(
        mayStillBePropagating: state.mayStillBePropagating,
        retryAttempt: state.retryAttempt,
        onRetry: () => context.read<SharedFileCubit>().retry(),
      );
    }

    if (state is SharedFileLoadFailure) {
      return SharedFileNetworkErrorView(
        onRetry: () => context.read<SharedFileCubit>().retry(),
      );
    }

    return const SharedFileResolvingView();
  }

  Widget _buildLocked(
    BuildContext context, {
    SharedFileLinkPayload? payload,
    String? errorMessage,
    bool isBusy = false,
  }) {
    return SharedFileLockedView(
      controller: _keyController,
      payload: payload,
      errorMessage: errorMessage,
      rememberKey: _rememberKey,
      isBusy: isBusy,
      onRememberChanged: (value) => setState(() {
        _rememberKey = value;

        if (!value) {
          unawaited(_keySession.forget(_fileId));
        }
      }),
      onSubmit: (rawKey) => _submitKey(context, rawKey),
    );
  }

  void _submitKey(BuildContext context, String rawKey) {
    setState(() {
      _isUnlocking = true;
      _keyToRemember = _rememberKey ? rawKey : null;
    });

    context.read<SharedFileCubit>().submit(rawKey);
  }

  /// Unlocks with the key this tab already accepted, if there is one.
  ///
  /// Runs at most once per page: a key that fails is forgotten by
  /// [_onStateChanged], and nothing re-reads it afterwards.
  void _tryRememberedKey(BuildContext context) {
    if (_hasTriedRememberedKey) {
      return;
    }

    _hasTriedRememberedKey = true;

    final cubit = context.read<SharedFileCubit>();

    _keySession.read(_fileId).then((rawKey) {
      if (!mounted || rawKey == null) {
        return;
      }

      _keyController.text = rawKey;

      setState(() {
        _rememberKey = true;
        _isUnlocking = true;
        _keyToRemember = rawKey;
      });

      cubit.submit(rawKey);
    });
  }
}
