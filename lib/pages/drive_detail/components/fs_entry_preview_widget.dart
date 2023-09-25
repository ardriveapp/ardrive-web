part of '../drive_detail_page.dart';

const List<double> _speedOptions = [.25, .5, .75, 1, 1.25, 1.5, 1.75, 2];

class FsEntryPreviewWidget extends StatefulWidget {
  const FsEntryPreviewWidget({
    Key? key,
    required this.state,
  }) : super(key: key);

  final FsEntryPreviewSuccess state;

  @override
  State<FsEntryPreviewWidget> createState() => _FsEntryPreviewWidgetState();
}

class _FsEntryPreviewWidgetState extends State<FsEntryPreviewWidget> {
  @override
  Widget build(BuildContext context) {
    switch (widget.state.runtimeType) {
      case FsEntryPreviewLoading:
        return const Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(),
          ),
        );

      case FsEntryPreviewImage:
        return ArDriveImage(
          fit: BoxFit.contain,
          height: double.maxFinite,
          width: double.maxFinite,
          image: MemoryImage(
            (widget.state as FsEntryPreviewImage).imageBytes,
          ),
        );

      case FsEntryPreviewAudio:
        return AudioPlayerWidget(
          filename: (widget.state as FsEntryPreviewAudio).filename,
          audioUrl: (widget.state as FsEntryPreviewAudio).previewUrl,
        );

      default:
        return VideoPlayerWidget(
          filename: (widget.state as FsEntryPreviewVideo).filename,
          videoUrl: (widget.state as FsEntryPreviewVideo).previewUrl,
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

  const VideoPlayerWidget(
      {Key? key, required this.filename, required this.videoUrl})
      : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _videoPlayerController;
  late VideoPlayer _videoPlayer;

  @override
  void initState() {
    logger.d('Initializing video player: ${widget.videoUrl}');
    super.initState();
    _videoPlayerController =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _videoPlayerController.initialize();
    _videoPlayerController.addListener(_listener);
    _videoPlayer =
        VideoPlayer(_videoPlayerController, key: const Key('videoPlayer'));
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
        logger.d('>>> ${_videoPlayerController.value.errorDescription}');

        // FIXME: This is a hack to deal with Chrome having problems on pressing
        // play after pause rapidly. Also happens when a video reaches its end
        // and a user plays it again right away.
        // The error message is:
        // "The play() request was interrupted by a call to pause(). https://goo.gl/LdLk22"
        // A better fix is required but putting this in for now.
        _videoPlayerController.removeListener(_listener);
        _videoPlayerController.dispose();

        _videoPlayerController =
            VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
        _videoPlayerController.initialize();
        _videoPlayerController.addListener(_listener);

        _videoPlayer =
            VideoPlayer(_videoPlayerController, key: const Key('videoPlayer'));
      }
    });
  }

  void goFullScreen() {
    final fsController =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    fsController.initialize().then((_) {
      fsController.seekTo(_videoPlayerController.value.position);
      fsController.play();
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          body: Center(
            child: TapRegion(
                onTapInside: (v) {
                  _videoPlayerController.seekTo(fsController.value.position);
                  Navigator.of(context).pop();
                },
                child: AspectRatio(
                    aspectRatio: _videoPlayerController.value.aspectRatio,
                    child: VideoPlayer(fsController))),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var colors = ArDriveTheme.of(context).themeData.colors;
    var videoValue = _videoPlayerController.value;
    var currentTime = getTimeString(videoValue.position);
    var duration = getTimeString(videoValue.duration);

    return VisibilityDetector(
        key: const Key('video-player'),
        onVisibilityChanged: (VisibilityInfo info) {
          if (mounted) {
            setState(
              () {
                // if (_videoPlayerController.value.isInitialized) {
                //   _isPlaying = info.visibleFraction > 0.5;
                //   _isPlaying
                //       ? _videoPlayerController.play()
                //       : _videoPlayerController.pause();
                // }
              },
            );
          }
        },
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(children: [
              Expanded(
                  child: AspectRatio(
                      aspectRatio: _videoPlayerController.value.aspectRatio,
                      child: TapRegion(
                          onTapInside: (v) {
                            goFullScreen();
                          },
                          child: _videoPlayer))),
              const SizedBox(height: 8),
              Column(children: [
                Text(widget.filename,
                    style: ArDriveTypography.body
                        .smallBold700(color: colors.themeFgDefault)),
                const SizedBox(height: 4),
                const Text('metadata'),
                const SizedBox(height: 8),
                Slider(
                    value: min(videoValue.position.inMilliseconds.toDouble(),
                        videoValue.duration.inMilliseconds.toDouble()),
                    min: 0.0,
                    max: videoValue.duration.inMilliseconds.toDouble(),
                    onChangeStart: (v) {
                      setState(() {
                        if (_videoPlayerController.value.duration >
                            Duration.zero) {
                          _videoPlayerController.pause();
                        }
                      });
                    },
                    onChanged: (v) {
                      setState(() {
                        if (_videoPlayerController.value.duration >
                            Duration.zero) {
                          _videoPlayerController
                              .seekTo(Duration(milliseconds: v.toInt()));
                        }
                      });
                    },
                    onChangeEnd: (v) {
                      setState(() {
                        if (_videoPlayerController.value.duration >
                            Duration.zero) {
                          // _videoPlayerController
                          //     .seekTo(Duration(milliseconds: v.toInt()));
                          _videoPlayerController.play();
                        }
                      });
                    }),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(currentTime),
                    const Expanded(child: SizedBox.shrink()),
                    Text(duration)
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                        onPressed: () {
                          setState(() {
                            if (!_videoPlayerController.value.isInitialized ||
                                _videoPlayerController.value.isBuffering ||
                                _videoPlayerController.value.duration <=
                                    Duration.zero) {
                              return;
                            }
                            final videoValue = _videoPlayerController.value;
                            final newPosition = videoValue.position -
                                const Duration(seconds: 15);
                            _videoPlayerController.seekTo(newPosition);
                          });
                        },
                        icon: const Icon(Icons.fast_rewind_outlined, size: 24)),
                    MaterialButton(
                      onPressed: () {
                        setState(() {
                          final value = _videoPlayerController.value;
                          if (!value.isInitialized ||
                              value.isBuffering ||
                              value.duration <= Duration.zero) {
                            return;
                          }
                          if (_videoPlayerController.value.isPlaying) {
                            _videoPlayerController.pause();
                          } else {
                            if (value.position >= value.duration) {
                              _videoPlayerController.seekTo(Duration.zero);
                            }
                            _videoPlayerController.play();
                          }
                        });
                      },
                      color: colors.themeAccentBrand,
                      shape: const CircleBorder(),
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: (_videoPlayerController.value.isPlaying)
                              ? const Icon(Icons.pause_outlined, size: 32)
                              : const Icon(Icons.play_arrow_outlined,
                                  size: 32)),
                    ),
                    IconButton(
                        onPressed: () {
                          setState(() {
                            if (!_videoPlayerController.value.isInitialized ||
                                _videoPlayerController.value.isBuffering ||
                                _videoPlayerController.value.duration <=
                                    Duration.zero) {
                              return;
                            }
                            final videoValue = _videoPlayerController.value;
                            final newPosition = videoValue.position +
                                const Duration(seconds: 15);

                            _videoPlayerController.seekTo(newPosition);
                          });
                        },
                        icon: const Icon(Icons.fast_forward_outlined, size: 24))
                  ],
                )
              ])
            ])));
  }
}

class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  final String filename;

  const AudioPlayerWidget(
      {Key? key, required this.filename, required this.audioUrl})
      : super(key: key);

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
      logger.d('Error setting audio url: $e');
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
                          style: ArDriveTypography.body
                              .smallBold700(color: colors.themeFgDefault)),
                      const SizedBox(height: 8),
                      SliderTheme(
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
                              value: _loadState == LoadState.failed
                                  ? 0
                                  : min(
                                      player.position.inMilliseconds.toDouble(),
                                      player.duration?.inMilliseconds
                                              .toDouble() ??
                                          0,
                                    ),
                              min: 0.0,
                              max: player.duration?.inMilliseconds.toDouble() ??
                                  0,
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
                                        player.seek(
                                            Duration(milliseconds: v.toInt()));
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
                                    })),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(currentTime),
                          const Expanded(child: SizedBox.shrink()),
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
