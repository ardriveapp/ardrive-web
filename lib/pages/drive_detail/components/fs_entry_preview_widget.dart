part of '../drive_detail_page.dart';

const List<double> _speedOptions = [.25, .5, .75, 1, 1.25, 1.5, 1.75, 2];

class FsEntryPreviewWidget extends StatefulWidget {
  final bool isSharePage;
  final Function()? onPreviousImageNavigation;
  final Function()? onNextImageNavigation;
  final bool canNavigateThroughImages;
  final FsEntryPreviewState state;
  final FsEntryPreviewCubit previewCubit;

  const FsEntryPreviewWidget({
    super.key,
    required this.state,
    required this.isSharePage,
    this.onPreviousImageNavigation,
    this.onNextImageNavigation,
    required this.canNavigateThroughImages,
    required this.previewCubit,
  });

  @override
  State<FsEntryPreviewWidget> createState() => _FsEntryPreviewWidgetState();
}

/// The one layout every "not yet" and "not this time" of a preview is drawn
/// with: something to look at, a line of words, and at most one thing to do.
///
/// Before this, each state drew its own - a bare spinner in the players, a
/// spinner and caption for a download, an icon and a button for a failure -
/// and they read as three different designs. On a video's black stage it is
/// drawn [onDark], so the same words and the same button sit in the player
/// that will play the file.
class _PreviewStatusLayout extends StatelessWidget {
  const _PreviewStatusLayout({
    required this.leading,
    required this.label,
    this.action,
    this.onDark = false,
    this.isMessage = false,
  });

  final Widget leading;
  final String label;
  final Widget? action;
  final bool onDark;

  /// A sentence to read and act on - a prompt, a failure - rather than a
  /// running status. It gets the full text colour; a status gets a quieter
  /// one, still readable on an audio player's tinted stage.
  final bool isMessage;

  /// On a video's black stage: a message near-white, a status a step back.
  static const Color _messageOnDark = Color(0xF2FFFFFF);
  static const Color _statusOnDark = Color(0xBFFFFFFF);

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final action = this.action;

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: ArDriveTypography.body.captionRegular(
              color: onDark
                  ? (isMessage ? _messageOnDark : _statusOnDark)
                  : (isMessage ? colors.themeFgDefault : colors.themeFgMuted),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action,
          ],
        ],
      ),
    );

    // A player's stage on a phone can be shorter than a prompt with its
    // button: shrink to fit rather than overflow. The text still wraps at the
    // full width, so it is only scaled when it truly does not fit.
    return LayoutBuilder(builder: (context, box) {
      if (!box.hasBoundedWidth || !box.hasBoundedHeight) {
        return content;
      }

      return FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(width: box.maxWidth, child: content),
      );
    });
  }
}

/// A spinner sized to sit above a caption in [_PreviewStatusLayout].
class _PreviewSpinner extends StatelessWidget {
  const _PreviewSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 24,
      width: 24,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    );
  }
}

/// The icon above a caption: decorative, since the caption says the same in
/// words.
Widget _previewStatusIcon(
  BuildContext context,
  ArDriveIcon Function({double? size, Color? color}) icon, {
  required bool onDark,
}) {
  final colors = ArDriveTheme.of(context).themeData.colors;

  return ExcludeSemantics(
    child: icon(
      size: 24,
      color: onDark ? _PreviewStatusLayout._statusOnDark : colors.themeFgMuted,
    ),
  );
}

/// The button under a caption. On a dark stage the filled one: an outlined
/// button there is a dark outline on black.
///
/// Sized like the details panel's inline buttons, not the default's headline
/// type, which is meant for a dialog's call to action and outweighs the
/// caption above it.
Widget _previewStatusButton({
  required String text,
  required VoidCallback onPressed,
  required bool onDark,
}) {
  return ArDriveButton(
    style: onDark ? ArDriveButtonStyle.primary : ArDriveButtonStyle.secondary,
    text: text,
    maxHeight: 36,
    fontStyle: ArDriveTypography.body.buttonNormalBold(),
    onPressed: onPressed,
  );
}

/// A player that has its file and is getting ready to play it.
///
/// Public media streams, so there is no download to count: the player fetches
/// what it needs to start, and this is what it says meanwhile - in the same
/// words and the same place as a private file's download before it.
@visibleForTesting
class FsEntryPreviewStarting extends StatelessWidget {
  const FsEntryPreviewStarting({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return _PreviewStatusLayout(
      leading: const _PreviewSpinner(),
      label: appLocalizationsOf(context).previewLoading,
      onDark: onDark,
    );
  }
}

/// How far a buffered preview has got (#2206).
///
/// A bar with "18.2 MB of 47 MB" when the gateway said how much it would send,
/// a spinner with the running count when it did not, and "Decrypting..." once
/// the bytes are in - which is one opaque call with nothing honest to count.
/// The words matter as much as the bar: a wait that says what it is doing is
/// a wait people sit through, and one that does not is one they refresh away.
@visibleForTesting
class FsEntryPreviewProgress extends StatelessWidget {
  const FsEntryPreviewProgress({
    super.key,
    required this.state,
    this.onDark = false,
  });

  final FsEntryPreviewLoading state;
  final bool onDark;

  /// Wide enough to read as a bar, narrow enough for a phone's details panel.
  static const double barWidth = 200;

  @override
  Widget build(BuildContext context) {
    final fraction = state.fraction;
    final label = _label(context);
    final colors = ArDriveTheme.of(context).themeData.colors;

    return _PreviewStatusLayout(
      leading: fraction == null
          ? const _PreviewSpinner()
          // The spinner's own height, so swapping one for the other - the
          // gateway's length arriving a moment after the first byte - moves
          // nothing under it.
          : SizedBox(
              width: barWidth,
              height: 24,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 4,
                    // The track shows how far there is to go; the theme's
                    // default is the surface colour, so it would not show.
                    backgroundColor: onDark
                        ? const Color(0x33FFFFFF)
                        : colors.themeFgMuted.withOpacity(0.2),
                    semanticsLabel: label,
                    semanticsValue: '${(fraction * 100).round()}%',
                  ),
                ),
              ),
            ),
      label: label,
      onDark: onDark,
    );
  }

  String _label(BuildContext context) {
    final l10n = appLocalizationsOf(context);

    if (state.phase == FsEntryPreviewLoadPhase.decrypting) {
      return l10n.previewDecrypting;
    }

    final total = state.total;

    if (total != null && total > 0) {
      return l10n.previewDownloadedOf(
        filesize(state.received),
        filesize(total),
      );
    }

    // No length to measure against, but a count still says it is moving.
    return state.received > 0
        ? filesize(state.received)
        : l10n.previewDownloading;
  }
}

/// A large preview, offered rather than started.
///
/// Says what pressing it costs - the whole file, in bytes - because that is
/// the only thing the reader needs to decide, and the reason it waits at all.
@visibleForTesting
class FsEntryPreviewOnRequestPrompt extends StatelessWidget {
  const FsEntryPreviewOnRequestPrompt({
    super.key,
    required this.state,
    required this.onPreview,
    this.onDark = false,
  });

  final FsEntryPreviewOnRequest state;
  final VoidCallback onPreview;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);

    return _PreviewStatusLayout(
      leading:
          _previewStatusIcon(context, ArDriveIcons.eyeOpen, onDark: onDark),
      label: l10n.previewOnRequestNote(filesize(state.size)),
      action: _previewStatusButton(
        text: l10n.preview,
        onPressed: onPreview,
        onDark: onDark,
      ),
      onDark: onDark,
      isMessage: true,
    );
  }
}

/// A preview that was attempted and did not arrive - said, not hidden.
///
/// Retry is offered only when asking again could help: a download that no
/// gateway answered may well answer the second time, and bytes that would not
/// decrypt will not decrypt the second time either.
@visibleForTesting
class FsEntryPreviewFailedMessage extends StatelessWidget {
  const FsEntryPreviewFailedMessage({
    super.key,
    required this.state,
    required this.onRetry,
    this.onDark = false,
  });

  final FsEntryPreviewFailed state;
  final VoidCallback onRetry;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);

    return _PreviewStatusLayout(
      leading:
          _previewStatusIcon(context, ArDriveIcons.triangle, onDark: onDark),
      label: state.canRetry
          ? l10n.previewDownloadFailed
          : l10n.previewDecryptFailed,
      action: state.canRetry
          ? _previewStatusButton(
              text: l10n.tryAgain,
              onPressed: onRetry,
              onDark: onDark,
            )
          : null,
      onDark: onDark,
      isMessage: true,
    );
  }
}

class _FsEntryPreviewWidgetState extends State<FsEntryPreviewWidget> {
  @override
  Widget build(BuildContext context) {
    final stateType = widget.state.runtimeType;
    switch (stateType) {
      case const (FsEntryPreviewUnavailable):
        return Center(
          child: Text(appLocalizationsOf(context).previewUnavailable),
        );

      case const (FsEntryPreviewOversized):
        final oversizedState = widget.state as FsEntryPreviewOversized;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              appLocalizationsOf(context).filePreviewTooLarge(
                filesize(oversizedState.maxFileSize),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );

      case const (FsEntryPreviewLoading):
        final loading = widget.state as FsEntryPreviewLoading;
        return _inPlayer(
              loading.media,
              (onDark) =>
                  FsEntryPreviewProgress(state: loading, onDark: onDark),
            ) ??
            Center(child: FsEntryPreviewProgress(state: loading));

      case const (FsEntryPreviewOnRequest):
        final onRequest = widget.state as FsEntryPreviewOnRequest;
        return _inPlayer(
              onRequest.media,
              (onDark) => FsEntryPreviewOnRequestPrompt(
                state: onRequest,
                onPreview: widget.previewCubit.loadOnRequest,
                onDark: onDark,
              ),
            ) ??
            Center(
              child: FsEntryPreviewOnRequestPrompt(
                state: onRequest,
                onPreview: widget.previewCubit.loadOnRequest,
              ),
            );

      case const (FsEntryPreviewFailed):
        final failed = widget.state as FsEntryPreviewFailed;
        return _inPlayer(
              failed.media,
              (onDark) => FsEntryPreviewFailedMessage(
                state: failed,
                onRetry: widget.previewCubit.retry,
                onDark: onDark,
              ),
            ) ??
            Center(
              child: FsEntryPreviewFailedMessage(
                state: failed,
                onRetry: widget.previewCubit.retry,
              ),
            );

      case const (FsEntryPreviewInitial):
        return const Center(child: _PreviewSpinner());

      case const (FsEntryPreviewImage):
        return ImagePreviewWidget(
          isSharePage: widget.isSharePage,
          isFullScreen: false,
          onNextImageNavigate: widget.onNextImageNavigation,
          onPreviousImageNavigate: widget.onPreviousImageNavigation,
          canNavigateThroughImages: widget.canNavigateThroughImages,
          previewCubit: widget.previewCubit,
        );

      case const (FsEntryPreviewAudio):
        return AudioPlayerWidget(
          filename: (widget.state as FsEntryPreviewAudio).filename,
          audioUrl: (widget.state as FsEntryPreviewAudio).previewUrl,
          isSharePage: widget.isSharePage,
        );

      case const (FsEntryPreviewText):
        final textState = widget.state as FsEntryPreviewText;
        return DocumentPreviewWidget(
          filename: textState.filename,
          content: textState.content,
          contentType: textState.contentType,
          isSharePage: widget.isSharePage,
          fileItem: textState.fileItem,
        );

      case const (FsEntryPreviewEmail):
        return EmailPreviewWidget(
          state: widget.state as FsEntryPreviewEmail,
          isSharePage: widget.isSharePage,
          isFullScreen: false,
        );

      case const (FsEntryPreviewVideo):
        return VideoPlayerWidget(
          filename: (widget.state as FsEntryPreviewVideo).filename,
          videoUrl: (widget.state as FsEntryPreviewVideo).previewUrl,
          isSharePage: widget.isSharePage,
        );

      case const (FsEntryPreviewPdf):
        final pdfState = widget.state as FsEntryPreviewPdf;
        return PdfPreviewWidget(
          filename: pdfState.filename,
          previewUrl: pdfState.previewUrl,
          pdfBytes: pdfState.pdfBytes,
          canOpenOnGateway: pdfState.canOpenOnGateway,
        );

      default:
        // Any state without a dedicated branch renders nothing rather than
        // being blind-cast into a preview widget.
        return const SizedBox.shrink();
    }
  }

  /// A media preview that is not playing yet, drawn inside the player that
  /// will play it, or null for anything that is not media.
  ///
  /// The player is the same widget, in the same place, as the one the playing
  /// state builds - so when the file arrives Flutter keeps it, and it starts
  /// playing where the download was. A video's stage is black, so what is on
  /// it is drawn for a dark background; an audio player's follows the theme.
  Widget? _inPlayer(
    FsEntryPreviewMedia? media,
    Widget Function(bool onDark) stage,
  ) {
    if (media == null) {
      return null;
    }

    switch (media.kind) {
      case FsEntryPreviewMediaKind.video:
        return VideoPlayerWidget(
          filename: media.filename,
          videoUrl: null,
          isSharePage: widget.isSharePage,
          stage: stage(true),
        );
      case FsEntryPreviewMediaKind.audio:
        return AudioPlayerWidget(
          filename: media.filename,
          audioUrl: null,
          isSharePage: widget.isSharePage,
          stage: stage(false),
        );
    }
  }
}

String getTimeString(Duration duration) {
  int durSeconds = duration.inSeconds;
  const hour = 60 * 60;
  const minute = 60;

  final hours = (durSeconds / hour).floor();
  final minutes = ((durSeconds % hour) / minute).floor();
  final seconds = durSeconds % minute;

  String timeString = '';

  if (hours > 0) {
    timeString = '${hours.floor()}:';
  }

  timeString +=
      hours > 0 ? minutes.toString().padLeft(2, '0') : minutes.toString();
  timeString += ':';
  timeString += seconds.toString().padLeft(2, '0');

  return timeString;
}

/// The inline video player - and, before it has a file, the frame the file
/// will play in.
///
/// With no [videoUrl] it creates no player at all: it draws its stage and its
/// controls, disabled, and puts [stage] on the stage - a private file's
/// download, the prompt for a large one, a failure. When the URL arrives the
/// same widget starts playing it, so nothing on screen moves except what is on
/// the stage. Before this, a private video was a spinner on the panel's
/// background that was swapped for a whole player at the end.
class VideoPlayerWidget extends StatefulWidget {
  final String? videoUrl;
  final String filename;
  final bool isSharePage;

  /// What the stage shows until there is a picture. Without one, a player
  /// that is starting says so ([FsEntryPreviewStarting]).
  final Widget? stage;

  const VideoPlayerWidget({
    super.key,
    required this.filename,
    required this.videoUrl,
    required this.isSharePage,
    this.stage,
  });

  @override
  // ignore: library_private_types_in_public_api
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;

  /// What the player is doing, or - with no file yet - that it is doing
  /// nothing, which every control below already treats as "not ready".
  VideoPlayerValue get _value =>
      _controller?.value ?? const VideoPlayerValue.uninitialized();
  bool _isVolumeSliderVisible = false;
  bool _wasPlaying = false;
  final _menuController = MenuController();
  final Lock _lock = Lock();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _start(widget.videoUrl);
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The file has arrived - or is a different file. A player that kept the
    // old one played the wrong thing, silently.
    if (oldWidget.videoUrl != widget.videoUrl) {
      _stop();
      _errorMessage = null;
      _start(widget.videoUrl);
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start(String? url) {
    // Waiting for a file: the frame stands, with [VideoPlayerWidget.stage] in it.
    if (url == null) {
      return;
    }

    logger.d('Initializing video player: $url');

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;

    controller.initialize().then((_) {
      // Replaced or gone while it was starting.
      if (!mounted || _controller != controller) {
        return;
      }

      controller.addListener(_listener);
      setState(() {});
    }).catchError((err) {
      if (!mounted || _controller != controller) {
        return;
      }

      setState(() => _errorMessage = _describeError(err.toString()));
    });
  }

  void _stop() {
    final controller = _controller;

    if (controller == null) {
      return;
    }

    logger.d('Disposing video player');
    controller.removeListener(_listener);
    controller.dispose();
    _controller = null;
  }

  String _describeError(String? error) {
    final formatError = error?.contains('MEDIA_ERR_SRC_NOT_SUPPORTED') ?? false;

    return formatError
        ? appLocalizationsOf(context).fileTypeUnsupported
        : appLocalizationsOf(context).couldNotLoadFile;
  }

  void _listener() {
    final value = _value;

    if (value.hasError) {
      logger.e('Video player error: ${value.errorDescription}');
    }

    // One rebuild per tick of the player, error or not. This used to call
    // setState inside setState.
    setState(() {
      if (value.hasError) {
        _errorMessage = _describeError(value.errorDescription);
      }
    });
  }

  void goFullScreen() {
    // Reachable only once the file is playing; a frame still waiting for one
    // has nothing to show full screen.
    final videoUrl = widget.videoUrl;

    if (videoUrl == null) {
      return;
    }

    bool wasPlaying = _value.isPlaying;
    if (wasPlaying) {
      _controller?.pause().catchError((error) {
        logger.e('Error pausing video: $error');
      });
    }

    Navigator.of(context).push(PageRouteBuilder(
        barrierDismissible: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            body: Center(
              child: FullScreenVideoPlayerWidget(
                filename: widget.filename,
                videoUrl: videoUrl,
                initialPosition: _value.position,
                initialIsPlaying: wasPlaying,
                initialVolume: _value.volume,
                onClose: (position, isPlaying, volume) async {
                  _controller?.seekTo(position);
                  _controller?.setVolume(volume);
                  if (isPlaying) {
                    await _lock.synchronized(() async {
                      await _controller?.play().catchError((e) {
                        logger.e('Error playing video: $e');
                      });
                    });
                  }
                },
                isSharePage: widget.isSharePage,
              ),
            ),
          );
        }));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final colors = ArDriveTheme.of(context).themeData.colors;
    final videoValue = _value;
    final currentTime = getTimeString(videoValue.position);
    final duration = getTimeString(videoValue.duration);

    final controlsEnabled = videoValue.isInitialized &&
        videoValue.duration > Duration.zero &&
        _errorMessage == null;

    var bufferedValue = videoValue.buffered.isNotEmpty
        ? videoValue.buffered.last.end.inMilliseconds.toDouble()
        : 0.0;

    return VisibilityDetector(
        key: const Key('video-player'),
        onVisibilityChanged: (VisibilityInfo info) async {
          if (mounted) {
            if (info.visibleFraction < 0.5 && _value.isPlaying) {
              await _lock.synchronized(() async {
                await _controller?.pause().catchError((error) {
                  logger.e('Error pausing video: $error');
                });
              });
            }
            setState(
              () {},
            );
          }
        },
        child: Column(children: [
          Expanded(
              child: Center(
                  child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              Center(
                  child: _errorMessage != null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _errorMessage ?? '',
                            textAlign: TextAlign.center,
                            style: ArDriveTypography.body
                                .smallBold700(color: colors.themeFgMuted)
                                .copyWith(fontSize: 13),
                          ))
                      : !videoValue.isInitialized
                          ? widget.stage ??
                              const FsEntryPreviewStarting(onDark: true)
                          : AspectRatio(
                              aspectRatio: _value.aspectRatio,
                              child: VideoPlayer(_controller!,
                                  key: const Key('videoPlayer')))),
            ],
          ))),
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(children: [
                Tooltip(
                  message: widget.filename,
                  child: Text(
                    widget.filename,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: ArDriveTypography.body.smallBold700(
                      color: colors.themeFgDefault,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (widget.isSharePage)
                      ScreenTypeLayout.builder(
                        desktop: (context) => Row(children: [
                          Text(currentTime),
                          const SizedBox(width: 8),
                        ]),
                        mobile: (context) => const SizedBox.shrink(),
                      ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                            trackHeight: 4,
                            trackShape:
                                _NoAdditionalHeightRoundedRectSliderTrackShape(),
                            inactiveTrackColor: colors.themeBgSubtle,
                            disabledThumbColor: colors.themeAccentBrand,
                            disabledInactiveTrackColor: colors.themeBgSubtle,
                            overlayShape: SliderComponentShape.noOverlay,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            )),
                        child: Slider(
                          value: min(
                              videoValue.position.inMilliseconds.toDouble(),
                              videoValue.duration.inMilliseconds.toDouble()),
                          secondaryTrackValue: bufferedValue,
                          min: 0.0,
                          max: videoValue.duration.inMilliseconds.toDouble(),
                          onChangeStart: !controlsEnabled
                              ? null
                              : (v) async {
                                  if (_value.duration > Duration.zero) {
                                    _wasPlaying = _value.isPlaying;
                                    if (_wasPlaying) {
                                      await _lock.synchronized(() async {
                                        await _controller
                                            ?.pause()
                                            .catchError((e) {
                                          logger.e('Error pausing video: $e');
                                        });
                                      });
                                      setState(() {});
                                    }
                                  }
                                },
                          onChanged: !controlsEnabled
                              ? null
                              : (v) async {
                                  setState(() {
                                    final milliseconds = v.toInt();

                                    if (_value.duration > Duration.zero) {
                                      _controller?.seekTo(
                                          Duration(milliseconds: milliseconds));
                                    }
                                  });
                                },
                          onChangeEnd: !controlsEnabled
                              ? null
                              : (v) async {
                                  if (_value.duration > Duration.zero &&
                                      _wasPlaying) {
                                    await _lock.synchronized(() async {
                                      await _controller?.play().catchError((e) {
                                        logger.e('Error playing video: $e');
                                      });
                                    });
                                    setState(() {});
                                  }
                                },
                        ),
                      ),
                    ),
                    if (widget.isSharePage)
                      ScreenTypeLayout.builder(
                        desktop: (context) => Row(children: [
                          const SizedBox(width: 8),
                          Text(duration),
                        ]),
                        mobile: (context) => const SizedBox.shrink(),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                ScreenTypeLayout.builder(
                  mobile: (BuildContext context) => const SizedBox.shrink(),
                  desktop: (BuildContext context) {
                    if (widget.isSharePage) {
                      return const SizedBox.shrink();
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            Text(currentTime),
                            const Expanded(child: SizedBox.shrink()),
                            Text(duration)
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
                MouseRegion(
                  onExit: (event) {
                    setState(() {
                      _isVolumeSliderVisible = false;
                    });
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: ScreenTypeLayout.builder(
                                mobile: (context) {
                                  if (widget.isSharePage) {
                                    return IconButton(
                                      onPressed: () {
                                        _displaySpeedOptionsModal(context, (v) {
                                          setState(() {
                                            _controller?.setPlaybackSpeed(v);
                                          });
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.settings_outlined,
                                        size: 24,
                                      ),
                                    );
                                  } else {
                                    return IconButton(
                                      tooltip:
                                          appLocalizationsOf(context).expand,
                                      onPressed: !controlsEnabled
                                          ? null
                                          : () {
                                              goFullScreen();
                                            },
                                      icon: const Icon(
                                        Icons.fullscreen_outlined,
                                        size: 24,
                                      ),
                                    );
                                  }
                                },
                                desktop: (context) => VolumeSliderWidget(
                                  volume: _value.volume,
                                  setVolume: (v) {
                                    setState(() {
                                      _controller?.setVolume(v);
                                    });
                                  },
                                  sliderVisible: _isVolumeSliderVisible,
                                  setSliderVisible: (v) {
                                    setState(() {
                                      _isVolumeSliderVisible = v;
                                    });
                                  },
                                ),
                              ))),
                      if (widget.isSharePage)
                        ScreenTypeLayout.builder(
                          desktop: (context) => IconButton.outlined(
                            onPressed: () {
                              setState(() {
                                _controller?.seekTo(_value.position -
                                    const Duration(seconds: 10));
                              });
                            },
                            icon: const Icon(Icons.replay_10, size: 24),
                          ),
                          mobile: (_) => const SizedBox.shrink(),
                        ),
                      MaterialButton(
                        onPressed: !controlsEnabled
                            ? null
                            : () async {
                                final value = _value;
                                if (!value.isInitialized ||
                                    value.isBuffering ||
                                    value.duration <= Duration.zero) {
                                  return;
                                }
                                if (value.isPlaying) {
                                  await _lock.synchronized(() async {
                                    await _controller?.pause().catchError((e) {
                                      logger.e('Error pausing video: $e');
                                    });
                                  });
                                } else {
                                  if (value.position >= value.duration) {
                                    _controller?.seekTo(Duration.zero);
                                  }

                                  await _lock.synchronized(() async {
                                    await _controller?.play().catchError((e) {
                                      logger.e('Error playing video: $e');
                                    });
                                  });
                                  setState(() {});
                                }
                              },
                        color: colors.themeAccentBrand,
                        disabledColor: colors.themeAccentDisabled,
                        shape: const CircleBorder(),
                        child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: (_value.isPlaying)
                                ? Icon(
                                    Icons.pause_outlined,
                                    size: 32,
                                    color: colors.themeFgOnAccent,
                                  )
                                : Icon(
                                    Icons.play_arrow_outlined,
                                    size: 32,
                                    color: colors.themeFgOnAccent,
                                  )),
                      ),
                      if (widget.isSharePage)
                        ScreenTypeLayout.builder(
                          desktop: (context) => IconButton.outlined(
                            onPressed: () {
                              setState(() {
                                _controller?.seekTo(_value.position +
                                    const Duration(seconds: 10));
                              });
                            },
                            icon: const Icon(Icons.forward_10, size: 24),
                          ),
                          mobile: (context) => const SizedBox.shrink(),
                        ),
                      Expanded(
                          child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ScreenTypeLayout.builder(
                              desktop: (context) => MenuAnchor(
                                menuChildren: [
                                  ..._speedOptions.map((v) {
                                    return ListTile(
                                      tileColor: colors.themeBgSurface,
                                      onTap: () {
                                        setState(() {
                                          _controller?.setPlaybackSpeed(v);
                                          _menuController.close();
                                        });
                                      },
                                      title: Text(
                                        v == 1.0
                                            ? appLocalizationsOf(context).normal
                                            : '$v',
                                        style: ArDriveTypography.body
                                            .buttonNormalBold(
                                                color: colors.themeFgDefault),
                                      ),
                                    );
                                  })
                                ],
                                controller: _menuController,
                                child: IconButton(
                                    onPressed: () {
                                      _menuController.open();
                                    },
                                    icon: const Icon(Icons.settings_outlined,
                                        size: 24)),
                              ),
                              mobile: (context) {
                                if (widget.isSharePage) {
                                  return IconButton(
                                    tooltip: appLocalizationsOf(context).expand,
                                    onPressed: !controlsEnabled
                                        ? null
                                        : () {
                                            goFullScreen();
                                          },
                                    icon: const Icon(
                                      Icons.fullscreen_outlined,
                                      size: 24,
                                    ),
                                  );
                                } else {
                                  return IconButton(
                                    onPressed: () {
                                      _displaySpeedOptionsModal(context, (v) {
                                        setState(() {
                                          _controller?.setPlaybackSpeed(v);
                                        });
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.settings_outlined,
                                      size: 24,
                                    ),
                                  );
                                }
                              },
                            ),
                            ScreenTypeLayout.builder(
                              desktop: (context) => IconButton(
                                  tooltip: appLocalizationsOf(context).expand,
                                  onPressed: !controlsEnabled
                                      ? null
                                      : () {
                                          goFullScreen();
                                        },
                                  icon: const Icon(Icons.fullscreen_outlined,
                                      size: 24)),
                              mobile: (context) => const SizedBox.shrink(),
                            )
                          ],
                        ),
                      ))
                    ],
                  ),
                )
              ]))
        ]));
  }

  @override
  bool get wantKeepAlive => true;
}

class FullScreenVideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String filename;
  final Duration initialPosition;
  final bool initialIsPlaying;
  final double initialVolume;
  final Function(Duration, bool, double) onClose;
  final bool isSharePage;

  const FullScreenVideoPlayerWidget({
    super.key,
    required this.filename,
    required this.videoUrl,
    required this.initialPosition,
    required this.initialIsPlaying,
    required this.initialVolume,
    required this.onClose,
    required this.isSharePage,
  });

  @override
  // ignore: library_private_types_in_public_api
  _FullScreenVideoPlayerWidgetState createState() =>
      _FullScreenVideoPlayerWidgetState();
}

class _FullScreenVideoPlayerWidgetState
    extends State<FullScreenVideoPlayerWidget> {
  late VideoPlayerController _videoPlayerController;
  VideoPlayer? _videoPlayer;
  bool _wasPlaying = false;
  bool _isVolumeSliderVisible = false;
  final _menuController = MenuController();
  bool _controlsVisible = true;
  bool _controlsDisabled = false;
  Timer? _hideControlsTimer;
  final Lock _lock = Lock();
  String? _errorMessage;

  @override
  void initState() {
    logger.d('Initializing video player: ${widget.videoUrl}');
    super.initState();
    _videoPlayerController =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _videoPlayerController.initialize().then((_) {
      _videoPlayerController.seekTo(widget.initialPosition).then((_) {
        _videoPlayerController.setVolume(widget.initialVolume);
        if (widget.initialIsPlaying) {
          _videoPlayerController.play().then((_) {
            setState(() {
              _videoPlayer = VideoPlayer(_videoPlayerController,
                  key: const Key('videoPlayer'));
            });
          }).catchError((e) {
            logger.e('Error playing video: $e');
          });
        } else {
          setState(() {
            _videoPlayer = VideoPlayer(_videoPlayerController,
                key: const Key('videoPlayer'));
          });
        }
      });
    });
    _videoPlayerController.addListener(_listener);

    MobileScreenOrientation.lockInLandscape();

    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _hideControls();
      }
    });
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _hideControls();
      }
    });
  }

  void _cancelHideControlsTimer() {
    _hideControlsTimer?.cancel();
  }

  void _showControls() {
    setState(() {
      _controlsVisible = true;
      MobileStatusBar.show();
    });
  }

  void _hideControls() {
    setState(() {
      _controlsVisible = false;
      MobileStatusBar.hide();
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _listener() {
    setState(() {
      if (_videoPlayerController.value.hasError) {
        logger.e('>>> ${_videoPlayerController.value.errorDescription}');
        setState(() {
          _errorMessage = appLocalizationsOf(context).couldNotLoadFile;
        });
      }
    });
  }

  @override
  void dispose() {
    MobileScreenOrientation.lockInPortraitUp();

    // Calling onClose() here to work when user hits close zoom button or hits
    // system back button on Android.
    widget.onClose(
      _videoPlayerController.value.position,
      _videoPlayerController.value.isPlaying,
      _videoPlayerController.value.volume,
    );

    logger.d('Disposing video player');
    _videoPlayerController.removeListener(_listener);
    _videoPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    var videoValue = _videoPlayerController.value;
    var currentTime = getTimeString(videoValue.position);
    var duration = getTimeString(videoValue.duration);

    var bufferedValue = videoValue.buffered.isNotEmpty
        ? videoValue.buffered.last.end.inMilliseconds.toDouble()
        : 0.0;

    return Scaffold(
      body: Center(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            Center(
                child: AspectRatio(
              aspectRatio: _videoPlayerController.value.aspectRatio,
              child: _errorMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _errorMessage ?? '',
                        textAlign: TextAlign.center,
                        style: ArDriveTypography.body
                            .smallBold700(color: colors.themeFgMuted)
                            .copyWith(fontSize: 13),
                      ))
                  : !videoValue.isInitialized
                      ? const FsEntryPreviewStarting(onDark: true)
                      : _videoPlayer ?? const SizedBox.shrink(),
            )),
            MouseRegion(
              onHover: (event) {
                if (!AppPlatform.isMobile) {
                  _showControls();
                  _resetHideControlsTimer();
                }
              },
              onExit: (event) {
                if (!AppPlatform.isMobile) {
                  if (mounted) {
                    setState(() {
                      _cancelHideControlsTimer();
                    });
                  }
                }
              },
              cursor: _controlsVisible
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.none,
              child: TapRegion(
                onTapInside: (event) {
                  _cancelHideControlsTimer();
                  _toggleControls();
                  if (_controlsVisible && !AppPlatform.isMobile) {
                    _resetHideControlsTimer();
                  }
                },
                child: Container(color: Colors.black.withOpacity(0.0)),
              ),
            ),
            AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              onEnd: () {
                setState(() {
                  _controlsDisabled = !_controlsVisible;
                });
              },
              child: _controlsDisabled
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        const Expanded(child: SizedBox.shrink()),
                        MouseRegion(
                          onHover: (event) {
                            _cancelHideControlsTimer();
                            if (!AppPlatform.isMobile && !_controlsVisible) {
                              _showControls();
                            }
                          },
                          child: TapRegion(
                            onTapInside: (event) {
                              if (AppPlatform.isMobile && !_controlsVisible) {
                                _cancelHideControlsTimer();
                                _showControls();
                              }
                            },
                            child: Container(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 20),
                              color: colors.themeBgCanvas,
                              child: Column(
                                children: [
                                  Tooltip(
                                    message: widget.filename,
                                    child: Text(widget.filename,
                                        style: ArDriveTypography.body
                                            .smallBold700(
                                                color: colors.themeFgDefault)),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(currentTime),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderThemeData(
                                              trackHeight: 4,
                                              trackShape:
                                                  _NoAdditionalHeightRoundedRectSliderTrackShape(),
                                              inactiveTrackColor:
                                                  colors.themeBgSubtle,
                                              disabledThumbColor:
                                                  colors.themeAccentBrand,
                                              disabledInactiveTrackColor:
                                                  colors.themeBgSubtle,
                                              overlayShape: SliderComponentShape
                                                  .noOverlay,
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                enabledThumbRadius: 8,
                                              )),
                                          child: Slider(
                                            value: min(
                                                videoValue
                                                    .position.inMilliseconds
                                                    .toDouble(),
                                                videoValue
                                                    .duration.inMilliseconds
                                                    .toDouble()),
                                            secondaryTrackValue: bufferedValue,
                                            min: 0.0,
                                            max: videoValue
                                                .duration.inMilliseconds
                                                .toDouble(),
                                            onChangeStart: (v) async {
                                              if (_videoPlayerController
                                                      .value.duration >
                                                  Duration.zero) {
                                                _wasPlaying =
                                                    _videoPlayerController
                                                        .value.isPlaying;
                                                if (_wasPlaying) {
                                                  await _lock
                                                      .synchronized(() async {
                                                    await _videoPlayerController
                                                        .pause()
                                                        .catchError((e) {
                                                      logger.e(
                                                          'Error pausing video: $e');
                                                    });

                                                    setState(() {});
                                                  });
                                                }
                                              }
                                            },
                                            onChanged: (v) async {
                                              if (_videoPlayerController
                                                      .value.duration >
                                                  Duration.zero) {
                                                _videoPlayerController.seekTo(
                                                    Duration(
                                                        milliseconds:
                                                            v.toInt()));
                                                setState(() {});
                                              }
                                            },
                                            onChangeEnd: (v) async {
                                              if (_videoPlayerController
                                                          .value.duration >
                                                      Duration.zero &&
                                                  _wasPlaying) {
                                                await _lock
                                                    .synchronized(() async {
                                                  await _videoPlayerController
                                                      .play()
                                                      .catchError((e) {
                                                    logger.e(
                                                        'Error playing video: $e');
                                                  });
                                                });
                                                setState(() {});
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(duration),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  MouseRegion(
                                    onExit: (event) {
                                      setState(() {
                                        _isVolumeSliderVisible = false;
                                      });
                                    },
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: SafeArea(
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: ScreenTypeLayout.builder(
                                                mobile: (context) => IconButton(
                                                    tooltip: appLocalizationsOf(
                                                            context)
                                                        .collapse,
                                                    onPressed: () {
                                                      Navigator.of(context)
                                                          .pop();
                                                    },
                                                    icon: const Icon(
                                                        Icons
                                                            .fullscreen_exit_outlined,
                                                        size: 24)),
                                                desktop: (context) => Row(
                                                  children: [
                                                    SizedBox(
                                                        width: 200,
                                                        child:
                                                            VolumeSliderWidget(
                                                          volume:
                                                              _videoPlayerController
                                                                  .value.volume,
                                                          setVolume: (v) {
                                                            setState(() {
                                                              _videoPlayerController
                                                                  .setVolume(v);
                                                            });
                                                          },
                                                          sliderVisible:
                                                              _isVolumeSliderVisible,
                                                          setSliderVisible:
                                                              (v) {
                                                            setState(() {
                                                              _isVolumeSliderVisible =
                                                                  v;
                                                            });
                                                          },
                                                        )),
                                                    const Expanded(
                                                        child:
                                                            SizedBox.shrink()),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        IconButton.outlined(
                                            onPressed: () {
                                              setState(() {
                                                _videoPlayerController.seekTo(
                                                    _videoPlayerController
                                                            .value.position -
                                                        const Duration(
                                                            seconds: 10));
                                              });
                                            },
                                            icon: const Icon(Icons.replay_10,
                                                size: 24)),
                                        MaterialButton(
                                          onPressed: () async {
                                            final value =
                                                _videoPlayerController.value;
                                            if (!value.isInitialized ||
                                                value.isBuffering ||
                                                value.duration <=
                                                    Duration.zero) {
                                              return;
                                            }
                                            if (value.isPlaying) {
                                              await _lock
                                                  .synchronized(() async {
                                                await _videoPlayerController
                                                    .pause()
                                                    .catchError((e) {
                                                  logger.e(
                                                      'Error pausing video: $e');
                                                });
                                              });
                                            } else {
                                              if (value.position >=
                                                  value.duration) {
                                                _videoPlayerController
                                                    .seekTo(Duration.zero);
                                              }
                                              await _lock.synchronized(
                                                () async {
                                                  await _videoPlayerController
                                                      .play()
                                                      .catchError(
                                                    (e) {
                                                      logger.e(
                                                          'Error playing video: $e');
                                                    },
                                                  );
                                                },
                                              );
                                            }
                                            setState(() {});
                                          },
                                          color: colors.themeAccentBrand,
                                          shape: const CircleBorder(),
                                          child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: (_videoPlayerController
                                                      .value.isPlaying)
                                                  ? Icon(
                                                      Icons.pause_outlined,
                                                      size: 32,
                                                      color: colors
                                                          .themeFgOnAccent,
                                                    )
                                                  : Icon(
                                                      Icons.play_arrow_outlined,
                                                      size: 32,
                                                      color: colors
                                                          .themeFgOnAccent,
                                                    )),
                                        ),
                                        IconButton.outlined(
                                          onPressed: () {
                                            setState(() {
                                              _videoPlayerController.seekTo(
                                                  _videoPlayerController
                                                          .value.position +
                                                      const Duration(
                                                          seconds: 10));
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.forward_10,
                                            size: 24,
                                          ),
                                        ),
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                ScreenTypeLayout.builder(
                                                  desktop: (context) =>
                                                      MenuAnchor(
                                                    menuChildren: [
                                                      ..._speedOptions.map((v) {
                                                        return ListTile(
                                                          tileColor: colors
                                                              .themeBgSurface,
                                                          onTap: () {
                                                            setState(() {
                                                              _videoPlayerController
                                                                  .setPlaybackSpeed(
                                                                      v);
                                                              _menuController
                                                                  .close();
                                                            });
                                                          },
                                                          title: Text(
                                                            v == 1.0
                                                                ? appLocalizationsOf(
                                                                        context)
                                                                    .normal
                                                                : '$v',
                                                            style: ArDriveTypography
                                                                .body
                                                                .buttonNormalBold(
                                                                    color: colors
                                                                        .themeFgDefault),
                                                          ),
                                                        );
                                                      })
                                                    ],
                                                    controller: _menuController,
                                                    child: IconButton(
                                                        onPressed: () {
                                                          _menuController
                                                              .open();
                                                        },
                                                        icon: const Icon(
                                                            Icons
                                                                .settings_outlined,
                                                            size: 24)),
                                                  ),
                                                  mobile: (context) =>
                                                      IconButton(
                                                    onPressed: () {
                                                      _displaySpeedOptionsModal(
                                                          context, (v) {
                                                        setState(() {
                                                          _videoPlayerController
                                                              .setPlaybackSpeed(
                                                                  v);
                                                        });
                                                      });
                                                    },
                                                    icon: const Icon(
                                                      Icons.settings_outlined,
                                                      size: 24,
                                                    ),
                                                  ),
                                                ),
                                                SafeArea(
                                                  child:
                                                      ScreenTypeLayout.builder(
                                                    desktop: (context) =>
                                                        IconButton(
                                                            tooltip:
                                                                appLocalizationsOf(
                                                                        context)
                                                                    .collapse,
                                                            onPressed: () {
                                                              Navigator.of(
                                                                      context)
                                                                  .pop();
                                                            },
                                                            icon: const Icon(
                                                                Icons
                                                                    .fullscreen_exit_outlined,
                                                                size: 24)),
                                                    mobile: (context) =>
                                                        const SizedBox.shrink(),
                                                  ),
                                                )
                                              ],
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ImagePreviewWidget extends StatefulWidget {
  final bool isSharePage;
  final bool isFullScreen;
  final Function? onPreviousImageNavigate;
  final Function? onNextImageNavigate;
  final bool canNavigateThroughImages;
  final FsEntryPreviewCubit previewCubit;

  const ImagePreviewWidget({
    super.key,
    this.isSharePage = false,
    this.isFullScreen = false,
    this.onPreviousImageNavigate,
    this.onNextImageNavigate,
    required this.canNavigateThroughImages,
    required this.previewCubit,
  });

  @override
  State<StatefulWidget> createState() {
    return _ImagePreviewWidgetState();
  }
}

class _ImagePreviewWidgetState extends State<ImagePreviewWidget> {
  bool _controlsVisible = true;
  bool _controlsDisabled = false;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _resetHideControlsTimer();
  }

  @override
  void dispose() {
    _cancelHideControlsTimer();
    if (widget.isFullScreen) {
      MobileStatusBar.show();
      MobileScreenOrientation.lockInPortraitUp();
    }
    super.dispose();
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _hideControls();
      }
    });
  }

  void _cancelHideControlsTimer() {
    _hideControlsTimer?.cancel();
  }

  void _showControls() {
    setState(() {
      _controlsVisible = true;
      if (widget.isFullScreen) {
        MobileStatusBar.show();
      }
    });
  }

  void _hideControls() {
    setState(() {
      _controlsVisible = false;
      if (widget.isFullScreen) {
        MobileStatusBar.hide();
      }
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isFullScreen) {
      return Center(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildActionBar(),
            ),
          ],
        ),
      );
    } else {
      return Column(
        children: [
          Flexible(child: _buildImage()),
          _buildActionBar(),
        ],
      );
    }
  }

  Widget _buildImage() {
    return ValueListenableBuilder(
      valueListenable: FsEntryPreviewCubit.imagePreviewNotifier,
      builder: (context, imagePreview, _) {
        if (imagePreview == null) {
          return const SizedBox.shrink();
        }

        final isLoading = imagePreview.isLoading;

        if (!widget.isFullScreen) {
          return _buildImageFromBytes(
            imagePreview.dataBytes,
            withTapRegion: false,
            isLoading: isLoading,
          );
        } else {
          return _buildImageFromBytes(
            imagePreview.dataBytes,
            withTapRegion: true,
            isLoading: isLoading,
          );
        }
      },
    );
  }

  Widget _buildImageFromBytes(
    Uint8List? imageBytes, {
    required bool withTapRegion,
    required bool isLoading,
  }) {
    final Widget content;

    if (isLoading) {
      content = const Center(child: _PreviewSpinner());
    } else {
      if (imageBytes == null) {
        content = const UnpreviewableContent();
      } else {
        content = ArDriveImage(
          fit: BoxFit.contain,
          height: double.maxFinite,
          width: double.maxFinite,
          image: MemoryImage(
            imageBytes,
          ),
        );
      }
    }

    if (!withTapRegion) {
      return content;
    }
    return MouseRegion(
      onHover: (event) {
        if (!AppPlatform.isMobile) {
          _showControls();
          _resetHideControlsTimer();
        }
      },
      onExit: (event) {
        if (!AppPlatform.isMobile) {
          if (mounted) {
            setState(() {
              _cancelHideControlsTimer();
            });
          }
        }
      },
      cursor:
          _controlsVisible ? SystemMouseCursors.click : SystemMouseCursors.none,
      hitTestBehavior: HitTestBehavior.opaque,
      child: TapRegion(
        behavior: HitTestBehavior.opaque,
        onTapInside: (event) {
          setState(() {
            _cancelHideControlsTimer();
            _toggleControls();

            if (_controlsVisible && !AppPlatform.isMobile) {
              _resetHideControlsTimer();
            }
          });
        },
        child: content,
      ),
    );
  }

  Widget _buildActionBar() {
    final theme = ArDriveTheme.of(context);
    final isFileExplorer = !widget.isSharePage && !widget.isFullScreen;
    final isFileExplorerFullScreen = !widget.isSharePage && widget.isFullScreen;

    final navigationHandlersSet = widget.onPreviousImageNavigate != null &&
        widget.onNextImageNavigate != null;

    // Inline on the share page, the name and type are already on the page -
    // the name beside the thumbnail at the top of the card, the type in File
    // details - so repeating them here spent a 96px minimum, a fifth of the
    // pane, saying what the recipient had already read. Expand is the only
    // thing in this bar the page cannot say for itself.
    //
    // Full screen is the exception and keeps them: the card is gone, so the
    // name is no longer anywhere else.
    final isSharePageInline = widget.isSharePage && !widget.isFullScreen;

    late Widget actionBar;

    if (isSharePageInline) {
      actionBar = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [_buildFullScreenButton(compact: true)],
      );
    } else if (isFileExplorer && navigationHandlersSet) {
      actionBar = Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: _buildNameAndExtension(isFileExplorer: isFileExplorer),
            )
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Flexible(
              flex: 1,
              child: Center(child: SizedBox.shrink()),
            ),
            Flexible(
              flex: 2,
              child: Center(
                child: _buildNavigationButtons(isFullScreen: false),
              ),
            ),
            Flexible(
              flex: 1,
              child: Center(
                child: _buildFullScreenButton(),
              ),
            ),
          ],
        ),
      ]);
    } else if (isFileExplorerFullScreen && navigationHandlersSet) {
      actionBar = Row(children: [
        Flexible(
          flex: 1,
          child: Row(
            children: [
              const SizedBox(
                width: 18,
              ),
              Flexible(
                  child:
                      _buildNameAndExtension(isFileExplorer: isFileExplorer)),
            ],
          ),
        ),
        Flexible(
          flex: 1,
          child: Center(
            child: _buildNavigationButtons(isFullScreen: true),
          ),
        ),
        Flexible(
          flex: 1,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildFullScreenButton(),
              const SizedBox(width: 24),
            ],
          ),
        ),
      ]);
    } else {
      actionBar = Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: _buildNameAndExtension(isFileExplorer: isFileExplorer),
          ),
          _buildFullScreenButton(),
        ],
      );
    }

    if (widget.isFullScreen) {
      return AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        onEnd: () {
          setState(() {
            _controlsDisabled = !_controlsVisible;
          });
        },
        child: MouseRegion(
          onHover: (event) {
            _cancelHideControlsTimer();
            if (!AppPlatform.isMobile && !_controlsVisible) {
              _showControls();
            }
          },
          child: Container(
            color: theme.themeData.colors.themeBgCanvas,
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: _controlsDisabled ? const SizedBox.shrink() : actionBar,
            ),
          ),
        ),
      );
    } else {
      return Container(
        color: theme.themeData.colors.themeBgCanvas,
        child: actionBar,
      );
    }
  }

  Widget _buildNameAndExtension({required bool isFileExplorer}) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: isFileExplorer ? 0 : 96,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: isFileExplorer ? 0 : 24,
          top: 24,
          bottom: isFileExplorer ? 0 : 24,
        ),
        child: ValueListenableBuilder(
          valueListenable: FsEntryPreviewCubit.imagePreviewNotifier,
          builder: (context, imagePreview, _) {
            if (imagePreview == null) {
              return const SizedBox.shrink();
            }

            final filename = imagePreview.filename;
            final contentType = imagePreview.contentType;
            final fileNameWithoutExtension =
                getBasenameWithoutExtension(filePath: filename);
            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: isFileExplorer
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: fileNameWithoutExtension,
                  child: Text(
                    fileNameWithoutExtension,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: ArDriveTypography.body.smallBold700(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
                    ),
                  ),
                ),
                Text(
                  getFileTypeFromMime(
                    contentType: contentType,
                  ).toUpperCase(),
                  style: ArDriveTypography.body.smallRegular(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDisabled,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNavigationButtons({
    required bool isFullScreen,
  }) {
    return Row(
      mainAxisAlignment: isFullScreen
          ? MainAxisAlignment.spaceEvenly
          : MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: widget.canNavigateThroughImages
              ? () => widget.onPreviousImageNavigate?.call()
              : null,
          icon: const Icon(Icons.arrow_back_ios_outlined),
        ),
        IconButton(
          onPressed: widget.canNavigateThroughImages
              ? () => widget.onNextImageNavigate?.call()
              : null,
          icon: const Icon(Icons.arrow_forward_ios_outlined),
        ),
      ],
    );
  }

  Widget _buildFullScreenButton({bool compact = false}) {
    return SafeArea(
      child: Padding(
        // The button keeps its 48px tap target either way; only the space
        // around it goes, since there is no longer a block of text to sit
        // level with.
        padding: compact
            ? const EdgeInsets.all(4)
            : const EdgeInsets.only(
                left: 24,
                top: 24,
                bottom: 24,
              ),
        child: IconButton(
          tooltip: widget.isFullScreen
              ? appLocalizationsOf(context).collapse
              : appLocalizationsOf(context).expand,
          onPressed: _toggleFullScreen,
          icon: widget.isFullScreen
              ? const Icon(Icons.fullscreen_exit_outlined)
              : const Icon(Icons.fullscreen_outlined, size: 24),
        ),
      ),
    );
  }

  Future<void> _toggleFullScreen() async {
    if (widget.isFullScreen) {
      Navigator.of(context).pop();
    } else {
      MobileScreenOrientation.lockInLandscape();
      await Navigator.of(context).push(
        PageRouteBuilder(
          barrierDismissible: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, __) => Scaffold(
            body: ImagePreviewWidget(
              isFullScreen: true,
              onPreviousImageNavigate: widget.onPreviousImageNavigate,
              onNextImageNavigate: widget.onNextImageNavigate,
              canNavigateThroughImages: widget.canNavigateThroughImages,
              previewCubit: widget.previewCubit,
            ),
          ),
        ),
      );
    }
  }
}

/// The inline audio player - and, before it has a file, the frame the file
/// will play in. See [VideoPlayerWidget], which works the same way.
///
/// It used to show a bare spinner, with no frame at all, until the audio had
/// loaded, and then the whole player appeared at once.
class AudioPlayerWidget extends StatefulWidget {
  final String? audioUrl;
  final String filename;
  final bool isSharePage;

  /// What the stage shows until there is audio. Without one, a player that is
  /// starting says so ([FsEntryPreviewStarting]).
  final Widget? stage;

  const AudioPlayerWidget({
    super.key,
    required this.filename,
    required this.audioUrl,
    required this.isSharePage,
    this.stage,
  });

  @override
  // ignore: library_private_types_in_public_api
  _AudioPlayerWidgetState createState() => _AudioPlayerWidgetState();
}

enum _AudioLoadState { loading, loaded, failed }

class _AudioPlayerWidgetState extends State<AudioPlayerWidget>
    with AutomaticKeepAliveClientMixin {
  /// Null until there is a file to play.
  AudioPlayer? _player;
  _AudioLoadState _loadState = _AudioLoadState.loading;
  bool _isVolumeSliderVisible = false;
  bool _wasPlaying = false;
  final _menuController = MenuController();
  StreamSubscription<Duration>? _positionListener;
  StreamSubscription<PlayerState>? _playStateListener;

  bool get _controlsEnabled => _loadState == _AudioLoadState.loaded;

  Duration get _position => _player?.position ?? Duration.zero;

  Duration? get _duration => _player?.duration;

  bool get _isPlaying => _player?.playing ?? false;

  bool get _isCompleted =>
      _player?.playerState.processingState == ProcessingState.completed;

  @override
  void initState() {
    super.initState();
    _start(widget.audioUrl);
  }

  @override
  void didUpdateWidget(covariant AudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.audioUrl != widget.audioUrl) {
      _stop();
      _loadState = _AudioLoadState.loading;
      _start(widget.audioUrl);
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start(String? url) {
    // Waiting for a file: the frame stands, with [AudioPlayerWidget.stage] in it.
    if (url == null) {
      return;
    }

    logger.d('Initializing audio player: $url');

    final player = AudioPlayer();
    _player = player;

    player.setUrl(url).then((_) {
      // Replaced or gone while it was loading.
      if (!mounted || _player != player) {
        return;
      }

      _positionListener = player.positionStream.listen((_) {
        setState(() {});
      });
      _playStateListener = player.playerStateStream.listen((event) {
        if (event.processingState == ProcessingState.completed) {
          player.stop();
        }
        setState(() {});
      });

      setState(() => _loadState = _AudioLoadState.loaded);
    }).catchError((e) {
      logger.e('Error setting audio url: $e');

      if (!mounted || _player != player) {
        return;
      }

      setState(() => _loadState = _AudioLoadState.failed);
    });
  }

  void _stop() {
    final player = _player;

    if (player == null) {
      return;
    }

    logger.d('Disposing audio player');
    _playStateListener?.cancel();
    _positionListener?.cancel();
    _playStateListener = null;
    _positionListener = null;
    player.stop();
    player.dispose();
    _player = null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    var colors = ArDriveTheme.of(context).themeData.colors;

    final currentTime = getTimeString(_position);
    final duration = _duration;
    final durationText = duration != null ? getTimeString(duration) : '0:00';

    final slider = SliderTheme(
        data: SliderThemeData(
            trackHeight: 4,
            trackShape: _NoAdditionalHeightRoundedRectSliderTrackShape(),
            inactiveTrackColor: colors.themeBgSubtle,
            disabledThumbColor: colors.themeAccentBrand,
            disabledInactiveTrackColor: colors.themeBgSubtle,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 8,
            )),
        child: Slider(
            value: !_controlsEnabled
                ? 0
                : min(
                    _position.inMilliseconds.toDouble(),
                    duration?.inMilliseconds.toDouble() ?? 0,
                  ),
            min: 0.0,
            max: duration?.inMilliseconds.toDouble() ?? 0,
            onChangeStart: !_controlsEnabled
                ? null
                : (v) {
                    setState(() {
                      _wasPlaying = _isPlaying;
                      if (_wasPlaying) {
                        _player?.pause();
                      }
                    });
                  },
            onChanged: !_controlsEnabled
                ? null
                : (v) {
                    setState(() {
                      _player?.seek(Duration(milliseconds: v.toInt()));
                    });
                  },
            onChangeEnd: !_controlsEnabled
                ? null
                : (v) {
                    setState(() {
                      if (_wasPlaying) {
                        _player?.play();
                      }
                    });
                  }));

    return VisibilityDetector(
        key: const Key('audio-player'),
        onVisibilityChanged: (VisibilityInfo info) {
          if (mounted) {
            setState(
              () {
                if (_isPlaying && info.visibleFraction < 0.5) {
                  _player?.pause();
                }
              },
            );
          }
        },
        child: Column(children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                Container(color: colors.themeBgSubtle),
                Align(
                  alignment: Alignment.center,
                  child: _buildStage(colors),
                ),
              ],
            ),
          ),
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(children: [
                Text(widget.filename,
                    textAlign: TextAlign.center,
                    style: ArDriveTypography.body
                        .smallBold700(color: colors.themeFgDefault)),
                if (!widget.isSharePage) ...[
                  const SizedBox(height: 8),
                  slider,
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(currentTime),
                    const SizedBox(width: 8),
                    widget.isSharePage
                        ? Expanded(child: slider)
                        : const Expanded(child: SizedBox.shrink()),
                    const SizedBox(width: 8),
                    Text(durationText)
                  ],
                ),
                const SizedBox(height: 8),
                MouseRegion(
                    onExit: (event) {
                      setState(() {
                        _isVolumeSliderVisible = false;
                      });
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: ScreenTypeLayout.builder(
                                  mobile: (context) => const SizedBox.shrink(),
                                  desktop: (context) => VolumeSliderWidget(
                                    volume: _player?.volume ?? 1,
                                    setVolume: (v) {
                                      setState(() {
                                        _player?.setVolume(v);
                                      });
                                    },
                                    sliderVisible: _isVolumeSliderVisible,
                                    setSliderVisible: (v) {
                                      setState(() {
                                        _isVolumeSliderVisible = v;
                                      });
                                    },
                                  ),
                                ))),
                        MaterialButton(
                          onPressed: !_controlsEnabled
                              ? null
                              : () {
                                  setState(() {
                                    if (_isCompleted || !_isPlaying) {
                                      if (_position == _duration) {
                                        _player?.stop();
                                        _player?.seek(Duration.zero);
                                      }
                                      _player?.play();
                                    } else {
                                      _player?.pause();
                                    }
                                  });
                                },
                          color: colors.themeAccentBrand,
                          disabledColor: colors.themeAccentDisabled,
                          shape: const CircleBorder(),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: (_isCompleted || !_isPlaying)
                                ? Icon(
                                    Icons.play_arrow_outlined,
                                    size: 32,
                                    color: colors.themeFgOnAccent,
                                  )
                                : Icon(
                                    Icons.pause_outlined,
                                    size: 32,
                                    color: colors.themeFgOnAccent,
                                  ),
                          ),
                        ),
                        Expanded(
                            child: Align(
                                alignment: Alignment.centerRight,
                                child: ScreenTypeLayout.builder(
                                    desktop: (context) => MenuAnchor(
                                          menuChildren: [
                                            ..._speedOptions.map((v) {
                                              return ListTile(
                                                tileColor:
                                                    colors.themeBgSurface,
                                                onTap: () {
                                                  setState(() {
                                                    _player?.setSpeed(v);
                                                    _menuController.close();
                                                  });
                                                },
                                                title: Text(
                                                  v == 1.0
                                                      ? appLocalizationsOf(
                                                              context)
                                                          .normal
                                                      : '$v',
                                                  style: ArDriveTypography.body
                                                      .buttonNormalBold(
                                                          color: colors
                                                              .themeFgDefault),
                                                ),
                                              );
                                            })
                                          ],
                                          controller: _menuController,
                                          child: IconButton(
                                              onPressed: () {
                                                _menuController.open();
                                              },
                                              icon: const Icon(
                                                  Icons.settings_outlined,
                                                  size: 24)),
                                        ),
                                    mobile: (context) => IconButton(
                                        onPressed: () {
                                          _displaySpeedOptionsModal(context,
                                              (v) {
                                            setState(() {
                                              _player?.setSpeed(v);
                                            });
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.settings_outlined,
                                            size: 24))))),
                      ],
                    ))
              ]))
        ]));
  }

  /// The stage: what the player is waiting for, that it is starting, that it
  /// could not play the file, or - once it can - the music glyph.
  Widget _buildStage(ArDriveColors colors) {
    if (_player == null) {
      return widget.stage ?? const FsEntryPreviewStarting();
    }

    switch (_loadState) {
      case _AudioLoadState.loading:
        return const FsEntryPreviewStarting();
      case _AudioLoadState.failed:
        return const FittedBox(
          fit: BoxFit.contain,
          child: UnpreviewableContent(),
        );
      case _AudioLoadState.loaded:
        return FittedBox(
          fit: BoxFit.contain,
          child: ArDriveIcons.music(size: 100, color: colors.themeFgMuted),
        );
    }
  }

  @override
  bool get wantKeepAlive => true;
}

class VolumeSliderWidget extends StatefulWidget {
  const VolumeSliderWidget({
    super.key,
    required this.volume,
    required this.setVolume,
    required this.sliderVisible,
    required this.setSliderVisible,
  });

  final double volume;
  final Function(double) setVolume;
  final bool sliderVisible;
  final Function(bool) setSliderVisible;

  @override
  State<VolumeSliderWidget> createState() => _VolumeSliderWidgetState();
}

class _VolumeSliderWidgetState extends State<VolumeSliderWidget> {
  double _lastVolume = 1.0;

  @override
  Widget build(BuildContext context) {
    var colors = ArDriveTheme.of(context).themeData.colors;

    bool isMuted = widget.volume <= 0;

    return Row(children: [
      MouseRegion(
        onEnter: (event) {
          widget.setSliderVisible(true);
        },
        child: IconButton(
            onPressed: () {
              setState(() {
                if (isMuted) {
                  widget.setVolume(_lastVolume);
                } else {
                  if (widget.volume > 0) {
                    _lastVolume = widget.volume;
                    widget.setVolume(0);
                  }
                }
              });
            },
            icon: Icon(
              isMuted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
              size: 24,
            )),
      ),
      Expanded(
          child: ClipRect(
              child: AnimatedSlide(
                  offset: Offset(widget.sliderVisible ? 0 : -1, 0),
                  duration: const Duration(milliseconds: 100),
                  child: SliderTheme(
                    data: SliderThemeData(
                        trackHeight: 4,
                        trackShape:
                            _NoAdditionalHeightRoundedRectSliderTrackShape(),
                        inactiveTrackColor: colors.themeBgSubtle,
                        activeTrackColor: colors.themeFgMuted,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbColor: colors.themeFgMuted,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        )),
                    child: Slider(
                      value: widget.volume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) {
                        widget.setVolume(v);
                      },
                      onChangeStart: (v) {
                        setState(() {
                          _lastVolume = v;
                        });
                      },
                    ),
                  ))))
    ]);
  }
}

class _NoAdditionalHeightRoundedRectSliderTrackShape
    extends RoundedRectSliderTrackShape {
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(context, offset,
        parentBox: parentBox,
        sliderTheme: sliderTheme,
        enableAnimation: enableAnimation,
        textDirection: textDirection,
        thumbCenter: thumbCenter,
        secondaryOffset: secondaryOffset,
        isDiscrete: isDiscrete,
        isEnabled: isEnabled,
        additionalActiveTrackHeight: 0);
  }
}

void _displaySpeedOptionsModal(
  BuildContext context,
  Function(double) setPlaybackSpeed,
) {
  final colors = ArDriveTheme.of(context).themeData.colors;
  final dropDownTheme = ArDriveTheme.of(context).themeData.dropdownTheme;

  showModalBottomSheet(
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(8),
      ),
    ),
    context: context,
    builder: (context) {
      return ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _speedOptions.length,
          itemBuilder: (context, index) {
            final speed = _speedOptions[index];
            return ListTile(
              tileColor: dropDownTheme.backgroundColor,
              hoverColor: dropDownTheme.hoverColor,
              textColor: colors.themeFgDefault,
              onTap: () {
                setPlaybackSpeed(speed);
                Navigator.of(context).pop();
              },
              title: Text(
                  speed == 1.0 ? appLocalizationsOf(context).normal : '$speed'),
            );
          },
        ),
      );
    },
  );
}
