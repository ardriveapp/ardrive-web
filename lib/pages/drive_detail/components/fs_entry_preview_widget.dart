part of '../drive_detail_page.dart';

const List<double> _speedOptions = [.25, .5, .75, 1, 1.25, 1.5, 1.75, 2];

class FsEntryPreviewWidget extends StatefulWidget {
  final bool isSharePage;

  const FsEntryPreviewWidget({
    Key? key,
    required this.state,
    required this.isSharePage,
  }) : super(key: key);

  final FsEntryPreviewState state;

  @override
  State<FsEntryPreviewWidget> createState() => _FsEntryPreviewWidgetState();
}

class _FsEntryPreviewWidgetState extends State<FsEntryPreviewWidget> {
  @override
  Widget build(BuildContext context) {
    switch (widget.state.runtimeType) {
      case FsEntryPreviewUnavailable:
        return const Center(
          child: Text('Preview unavailable'),
        );

      case FsEntryPreviewLoading:
      case FsEntryPreviewInitial:
        return const Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(),
          ),
        );

      case FsEntryPreviewImage:
        return ImagePreviewWidget(
          filename: (widget.state as FsEntryPreviewImage).filename,
          contentType: (widget.state as FsEntryPreviewImage).contentType,
          imageBytes: (widget.state as FsEntryPreviewImage).imageBytes,
          isSharePage: widget.isSharePage,
          isFullScreen: false,
        );

      case FsEntryPreviewAudio:
        return AudioPlayerWidget(
          filename: (widget.state as FsEntryPreviewAudio).filename,
          audioUrl: (widget.state as FsEntryPreviewAudio).previewUrl,
          isSharePage: widget.isSharePage,
        );

      default:
        return VideoPlayerWidget(
          filename: (widget.state as FsEntryPreviewVideo).filename,
          videoUrl: (widget.state as FsEntryPreviewVideo).previewUrl,
          isSharePage: widget.isSharePage,
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

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String filename;
  final bool isSharePage;

  const VideoPlayerWidget({
    Key? key,
    required this.filename,
    required this.videoUrl,
    required this.isSharePage,
  }) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with AutomaticKeepAliveClientMixin {
  late VideoPlayerController _videoPlayerController;
  bool _isVolumeSliderVisible = false;
  bool _wasPlaying = false;
  final _menuController = MenuController();
  final Lock _lock = Lock();
  String? _errorMessage;

  @override
  void initState() {
    logger.d('Initializing video player: ${widget.videoUrl}');
    super.initState();
    _videoPlayerController =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _videoPlayerController.initialize().then((v) {
      _videoPlayerController.addListener(_listener);
      // force refresh
      setState(() {});
    }).catchError((err) {
      final formatError =
          err.toString().contains('MEDIA_ERR_SRC_NOT_SUPPORTED');
      setState(() {
        _errorMessage = formatError
            ? appLocalizationsOf(context).fileTypeUnsupported
            : appLocalizationsOf(context).couldNotLoadFile;
      });
    });
  }

  @override
  void dispose() {
    logger.d('Disposing video player');
    _videoPlayerController.removeListener(_listener);
    _videoPlayerController.dispose();
    super.dispose();
  }

  void _listener() {
    setState(() {
      if (_videoPlayerController.value.hasError) {
        logger.e('>>> ${_videoPlayerController.value.errorDescription}');
        setState(() {
          final formatError = _videoPlayerController.value.errorDescription
                  ?.contains('MEDIA_ERR_SRC_NOT_SUPPORTED') ??
              false;

          _errorMessage = formatError
              ? appLocalizationsOf(context).fileTypeUnsupported
              : appLocalizationsOf(context).couldNotLoadFile;
        });
      }
    });
  }

  void goFullScreen() {
    bool wasPlaying = _videoPlayerController.value.isPlaying;
    if (wasPlaying) {
      _videoPlayerController.pause().catchError((error) {
        logger.e('Error pausing video: $error');
      });
    }

    Navigator.of(context).push(PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            body: Center(
              child: FullScreenVideoPlayerWidget(
                filename: widget.filename,
                videoUrl: widget.videoUrl,
                initialPosition: _videoPlayerController.value.position,
                initialIsPlaying: wasPlaying,
                initialVolume: _videoPlayerController.value.volume,
                onClose: (position, isPlaying, volume) async {
                  _videoPlayerController.seekTo(position);
                  _videoPlayerController.setVolume(volume);
                  if (isPlaying) {
                    await _lock.synchronized(() async {
                      await _videoPlayerController.play().catchError((e) {
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
    final videoValue = _videoPlayerController.value;
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
            if (info.visibleFraction < 0.5 &&
                _videoPlayerController.value.isPlaying) {
              await _lock.synchronized(() async {
                await _videoPlayerController.pause().catchError((error) {
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
                          ? const Center(
                              child: SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : AspectRatio(
                              aspectRatio:
                                  _videoPlayerController.value.aspectRatio,
                              child: VideoPlayer(_videoPlayerController,
                                  key: const Key('videoPlayer')))),
            ],
          ))),
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(children: [
                Text(widget.filename,
                    textAlign: TextAlign.center,
                    style: ArDriveTypography.body
                        .smallBold700(color: colors.themeFgDefault)),
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
                                  if (_videoPlayerController.value.duration >
                                      Duration.zero) {
                                    _wasPlaying =
                                        _videoPlayerController.value.isPlaying;
                                    if (_wasPlaying) {
                                      await _lock.synchronized(() async {
                                        await _videoPlayerController
                                            .pause()
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

                                    if (_videoPlayerController.value.duration >
                                        Duration.zero) {
                                      _videoPlayerController.seekTo(
                                          Duration(milliseconds: milliseconds));
                                    }
                                  });
                                },
                          onChangeEnd: !controlsEnabled
                              ? null
                              : (v) async {
                                  if (_videoPlayerController.value.duration >
                                          Duration.zero &&
                                      _wasPlaying) {
                                    await _lock.synchronized(() async {
                                      await _videoPlayerController
                                          .play()
                                          .catchError((e) {
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
                                            _videoPlayerController
                                                .setPlaybackSpeed(v);
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
                                  volume: _videoPlayerController.value.volume,
                                  setVolume: (v) {
                                    setState(() {
                                      _videoPlayerController.setVolume(v);
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
                                _videoPlayerController.seekTo(
                                    _videoPlayerController.value.position -
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
                                final value = _videoPlayerController.value;
                                if (!value.isInitialized ||
                                    value.isBuffering ||
                                    value.duration <= Duration.zero) {
                                  return;
                                }
                                if (value.isPlaying) {
                                  await _lock.synchronized(() async {
                                    await _videoPlayerController
                                        .pause()
                                        .catchError((e) {
                                      logger.e('Error pausing video: $e');
                                    });
                                  });
                                } else {
                                  if (value.position >= value.duration) {
                                    _videoPlayerController
                                        .seekTo(Duration.zero);
                                  }

                                  await _lock.synchronized(() async {
                                    await _videoPlayerController
                                        .play()
                                        .catchError((e) {
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
                            child: (_videoPlayerController.value.isPlaying)
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
                                _videoPlayerController.seekTo(
                                    _videoPlayerController.value.position +
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
                                          _videoPlayerController
                                              .setPlaybackSpeed(v);
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
                                          _videoPlayerController
                                              .setPlaybackSpeed(v);
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
    Key? key,
    required this.filename,
    required this.videoUrl,
    required this.initialPosition,
    required this.initialIsPlaying,
    required this.initialVolume,
    required this.onClose,
    required this.isSharePage,
  }) : super(key: key);

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

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);

    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

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
                  ? const Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _videoPlayer ?? const SizedBox.shrink(),
        )),
        MouseRegion(
          onHover: (event) {
            if (!AppPlatform.isMobile) {
              setState(() {
                _controlsVisible = true;
                _hideControlsTimer?.cancel();
                _hideControlsTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted) {
                    setState(() {
                      _controlsVisible = false;
                    });
                  }
                });
              });
            }
          },
          onExit: (event) {
            if (!AppPlatform.isMobile) {
              if (mounted) {
                setState(() {
                  _hideControlsTimer?.cancel();
                });
              }
            }
          },
          cursor: _controlsVisible
              ? SystemMouseCursors.click
              : SystemMouseCursors.none,
          child: TapRegion(
            onTapInside: (event) {
              setState(() {
                _hideControlsTimer?.cancel();
                _controlsVisible = !_controlsVisible;

                if (_controlsVisible && !AppPlatform.isMobile) {
                  _hideControlsTimer = Timer(const Duration(seconds: 3), () {
                    if (mounted) {
                      setState(() {
                        _controlsVisible = false;
                      });
                    }
                  });
                }
              });
            },
            child: Container(color: Colors.black.withOpacity(0.0)),
          ),
        ),
        AnimatedOpacity(
            opacity: _controlsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Column(
              children: [
                const Expanded(child: SizedBox.shrink()),
                MouseRegion(
                    onHover: (event) {
                      _hideControlsTimer?.cancel();
                      if (!AppPlatform.isMobile && !_controlsVisible) {
                        setState(() {
                          _controlsVisible = true;
                        });
                      }
                    },
                    child: TapRegion(
                        onTapInside: (event) {
                          if (AppPlatform.isMobile && !_controlsVisible) {
                            _hideControlsTimer?.cancel();
                            setState(() {
                              _controlsVisible = true;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                          color: colors.themeBgCanvas,
                          child: Column(children: [
                            Text(widget.filename,
                                style: ArDriveTypography.body.smallBold700(
                                    color: colors.themeFgDefault)),
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
                                            overlayShape:
                                                SliderComponentShape.noOverlay,
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
                                            }))),
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
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                      child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: ScreenTypeLayout.builder(
                                            mobile: (context) => IconButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                },
                                                icon: const Icon(
                                                    Icons
                                                        .fullscreen_exit_outlined,
                                                    size: 24)),
                                            desktop: (context) => Row(
                                              children: [
                                                SizedBox(
                                                    width: 200,
                                                    child: VolumeSliderWidget(
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
                                                      setSliderVisible: (v) {
                                                        setState(() {
                                                          _isVolumeSliderVisible =
                                                              v;
                                                        });
                                                      },
                                                    )),
                                                const Expanded(
                                                    child: SizedBox.shrink()),
                                              ],
                                            ),
                                          ))),
                                  IconButton.outlined(
                                      onPressed: () {
                                        setState(() {
                                          _videoPlayerController.seekTo(
                                              _videoPlayerController
                                                      .value.position -
                                                  const Duration(seconds: 10));
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
                                          value.duration <= Duration.zero) {
                                        return;
                                      }
                                      if (value.isPlaying) {
                                        await _lock.synchronized(() async {
                                          await _videoPlayerController
                                              .pause()
                                              .catchError((e) {
                                            logger.e('Error pausing video: $e');
                                          });
                                        });
                                      } else {
                                        if (value.position >= value.duration) {
                                          _videoPlayerController
                                              .seekTo(Duration.zero);
                                        }
                                        await _lock.synchronized(() async {
                                          await _videoPlayerController
                                              .play()
                                              .catchError((e) {
                                            logger.e('Error playing video: $e');
                                          });
                                        });
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
                                                color: colors.themeFgOnAccent,
                                              )
                                            : Icon(
                                                Icons.play_arrow_outlined,
                                                size: 32,
                                                color: colors.themeFgOnAccent,
                                              )),
                                  ),
                                  IconButton.outlined(
                                      onPressed: () {
                                        setState(() {
                                          _videoPlayerController.seekTo(
                                              _videoPlayerController
                                                      .value.position +
                                                  const Duration(seconds: 10));
                                        });
                                      },
                                      icon: const Icon(Icons.forward_10,
                                          size: 24)),
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
                                                        _menuController.open();
                                                      },
                                                      icon: const Icon(
                                                          Icons
                                                              .settings_outlined,
                                                          size: 24)),
                                                ),
                                            mobile: (context) => IconButton(
                                                onPressed: () {
                                                  _displaySpeedOptionsModal(
                                                      context, (v) {
                                                    setState(() {
                                                      _videoPlayerController
                                                          .setPlaybackSpeed(v);
                                                    });
                                                  });
                                                },
                                                icon: const Icon(
                                                    Icons.settings_outlined,
                                                    size: 24))),
                                        ScreenTypeLayout.builder(
                                          desktop: (context) => IconButton(
                                              onPressed: () {
                                                Navigator.of(context).pop();
                                              },
                                              icon: const Icon(
                                                  Icons
                                                      .fullscreen_exit_outlined,
                                                  size: 24)),
                                          mobile: (context) =>
                                              const SizedBox.shrink(),
                                        )
                                      ],
                                    ),
                                  ))
                                ],
                              ),
                            )
                          ]),
                        ))),
              ],
            )),
      ],
    )));
  }
}

class ImagePreviewFullScreenWidget extends StatefulWidget {
  final Uint8List imageBytes;
  final String filename;
  final String contentType;

  const ImagePreviewFullScreenWidget({
    super.key,
    required this.filename,
    required this.contentType,
    required this.imageBytes,
  });

  @override
  State<StatefulWidget> createState() {
    return _ImagePreviewFullScreenWidgetState();
  }
}

class _ImagePreviewFullScreenWidgetState
    extends State<ImagePreviewFullScreenWidget> {
  bool fullScreenMode = false;

  @override
  void initState() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);

    super.initState();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ImagePreviewWidget(
        filename: widget.filename,
        contentType: widget.contentType,
        imageBytes: widget.imageBytes,
        isFullScreen: true,
      ),
    );
  }
}

class ImagePreviewWidget extends StatefulWidget {
  final Uint8List imageBytes;
  final String filename;
  final String contentType;
  final bool isSharePage;
  final bool isFullScreen;

  const ImagePreviewWidget({
    super.key,
    required this.filename,
    required this.contentType,
    required this.imageBytes,
    this.isSharePage = false,
    this.isFullScreen = false,
  });

  @override
  State<StatefulWidget> createState() {
    return _ImagePreviewWidgetState();
  }
}

class _ImagePreviewWidgetState extends State<ImagePreviewWidget> {
  @override
  Widget build(BuildContext context) {
    if (!widget.isSharePage && !widget.isFullScreen) {
      return _buildImage();
    } else {
      final theme = ArDriveTheme.of(context);

      return Column(
        children: [
          Flexible(child: _buildImage()),
          Container(
            color: theme.themeData.colors.themeBgCanvas,
            child: _buildActionBar(),
          ),
        ],
      );
    }
  }

  Widget _buildImage() {
    return ArDriveImage(
      fit: BoxFit.contain,
      height: double.maxFinite,
      width: double.maxFinite,
      image: MemoryImage(
        widget.imageBytes,
      ),
    );
  }

  Widget _buildActionBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          height: 96,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 24,
              top: 24,
              bottom: 24,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getFileNameWithNoExtension(),
                  style: ArDriveTypography.body.smallBold700(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  ),
                ),
                Text(
                  _getFileExtension(),
                  style: ArDriveTypography.body.smallRegular(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            right: 24,
            top: 24,
            bottom: 24,
          ),
          child: IconButton(
            onPressed: goFullScreen,
            icon: widget.isFullScreen
                ? const Icon(Icons.fullscreen_exit_outlined)
                : const Icon(Icons.fullscreen_outlined, size: 24),
          ),
        ),
      ],
    );
  }

  String _getFileNameWithNoExtension() {
    return widget.filename.substring(0, widget.filename.lastIndexOf('.'));
  }

  String _getFileExtension() {
    return widget.contentType
        .substring(
          widget.contentType.lastIndexOf('/') + 1,
        )
        .toUpperCase();
  }

  void goFullScreen() {
    if (widget.isFullScreen) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, __) => ImagePreviewFullScreenWidget(
            filename: widget.filename,
            contentType: widget.contentType,
            imageBytes: widget.imageBytes,
          ),
        ),
      );
    }
  }
}

class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  final String filename;
  final bool isSharePage;

  const AudioPlayerWidget({
    Key? key,
    required this.filename,
    required this.audioUrl,
    required this.isSharePage,
  }) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _AudioPlayerWidgetState createState() => _AudioPlayerWidgetState();
}

enum LoadState { loading, loaded, failed }

class _AudioPlayerWidgetState extends State<AudioPlayerWidget>
    with AutomaticKeepAliveClientMixin {
  late AudioPlayer player;
  LoadState _loadState = LoadState.loading;
  bool _isVolumeSliderVisible = false;
  bool _wasPlaying = false;
  final _menuController = MenuController();
  StreamSubscription<Duration>? _positionListener;
  StreamSubscription<PlayerState>? _playStateListener;

  @override
  void initState() {
    logger.d('Initializing audio player: ${widget.audioUrl}');
    player = AudioPlayer();
    player.setUrl(widget.audioUrl).then((value) {
      setState(() {
        _loadState = LoadState.loaded;
        _positionListener = player.positionStream.listen((event) {
          setState(() {});
        });

        _playStateListener = player.playerStateStream.listen((event) {
          if (event.processingState == ProcessingState.completed) {
            player.stop();
          }
          setState(() {});
        });
      });
    }).catchError((e) {
      logger.e('Error setting audio url: $e');
      setState(() {
        _loadState = LoadState.failed;
      });
    });

    super.initState();
  }

  @override
  void dispose() {
    logger.d('Disposing audio player');
    player.stop();
    _playStateListener?.cancel();
    _positionListener?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    var colors = ArDriveTheme.of(context).themeData.colors;

    var currentTime = getTimeString(player.position);
    var duration =
        player.duration != null ? getTimeString(player.duration!) : '0:00';

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
            value: _loadState == LoadState.failed
                ? 0
                : min(
                    player.position.inMilliseconds.toDouble(),
                    player.duration?.inMilliseconds.toDouble() ?? 0,
                  ),
            min: 0.0,
            max: player.duration?.inMilliseconds.toDouble() ?? 0,
            onChangeStart: _loadState == LoadState.failed
                ? null
                : (v) {
                    setState(() {
                      _wasPlaying = player.playing;
                      if (_wasPlaying) {
                        player.pause();
                      }
                    });
                  },
            onChanged: _loadState == LoadState.failed
                ? null
                : (v) {
                    setState(() {
                      player.seek(Duration(milliseconds: v.toInt()));
                    });
                  },
            onChangeEnd: _loadState == LoadState.failed
                ? null
                : (v) {
                    setState(() {
                      if (_wasPlaying) {
                        player.play();
                      }
                    });
                  }));

    return VisibilityDetector(
        key: const Key('audio-player'),
        onVisibilityChanged: (VisibilityInfo info) {
          if (mounted) {
            setState(
              () {
                if (player.playing && info.visibleFraction < 0.5) {
                  player.pause();
                }
              },
            );
          }
        },
        child: _loadState == LoadState.loading
            ? const Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(),
                ),
              )
            : Column(children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      Container(color: colors.themeBgSubtle),
                      Align(
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: _loadState == LoadState.failed
                                ? Column(
                                    children: [
                                      const Icon(Icons.error_outline_outlined,
                                          size: 20),
                                      Text(
                                          appLocalizationsOf(context)
                                              .couldNotLoadFile,
                                          style: ArDriveTypography.body
                                              .smallBold700(
                                                  color: colors.themeFgMuted)
                                              .copyWith(fontSize: 13)),
                                    ],
                                  )
                                : ArDriveIcons.music(
                                    size: 100, color: colors.themeFgMuted),
                          )),
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
                          Text(duration)
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
                                        mobile: (context) =>
                                            const SizedBox.shrink(),
                                        desktop: (context) =>
                                            VolumeSliderWidget(
                                          volume: player.volume,
                                          setVolume: (v) {
                                            setState(() {
                                              player.setVolume(v);
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
                                onPressed: _loadState == LoadState.failed
                                    ? null
                                    : () {
                                        setState(() {
                                          if (player.playerState
                                                      .processingState ==
                                                  ProcessingState.completed ||
                                              !player.playing) {
                                            if (player.position ==
                                                player.duration) {
                                              player.stop();
                                              player.seek(Duration.zero);
                                            }
                                            player.play();
                                          } else {
                                            player.pause();
                                          }
                                        });
                                      },
                                color: colors.themeAccentBrand,
                                disabledColor: colors.themeAccentDisabled,
                                shape: const CircleBorder(),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: (player.playerState.processingState ==
                                              ProcessingState.completed ||
                                          !player.playing)
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
                                                          player.setSpeed(v);
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
                                                      _menuController.open();
                                                    },
                                                    icon: const Icon(
                                                        Icons.settings_outlined,
                                                        size: 24)),
                                              ),
                                          mobile: (context) => IconButton(
                                              onPressed: () {
                                                _displaySpeedOptionsModal(
                                                    context, (v) {
                                                  setState(() {
                                                    player.setSpeed(v);
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

  @override
  bool get wantKeepAlive => true;
}

class VolumeSliderWidget extends StatefulWidget {
  const VolumeSliderWidget({
    Key? key,
    required this.volume,
    required this.setVolume,
    required this.sliderVisible,
    required this.setSliderVisible,
  }) : super(key: key);

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
