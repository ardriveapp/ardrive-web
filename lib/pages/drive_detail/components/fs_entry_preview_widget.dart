part of '../drive_detail_page.dart';

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

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer player;
  LoadState _loadState = LoadState.loading;

  @override
  void initState() {
    logger.d('Initializing audio player: ${widget.audioUrl}');
    player = AudioPlayer();
    player.setUrl(widget.audioUrl).then((value) {
      setState(() {
        _loadState = LoadState.loaded;
        player.positionStream.listen((event) {
          setState(() {});
        });

        player.playerStateStream.listen((event) {
          // logger.d('Player state: $event');
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
    player.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    var colors = ArDriveTheme.of(context).themeData.colors;

    player.duration;

    var currentTime = getTimeString(player.position);
    var duration =
        player.duration != null ? getTimeString(player.duration!) : '0:00';

    return VisibilityDetector(
        key: const Key('audio-player'),
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
        child: _loadState == LoadState.loading
            ? const Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(),
                ),
              )
            : _loadState == LoadState.failed
                ? const Center(
                    child: Text('Failed to load audio'),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(children: [
                      Expanded(child: Container(color: Colors.black)),
                      const SizedBox(height: 8),
                      Column(children: [
                        Text(widget.filename,
                            style: ArDriveTypography.body
                                .smallBold700(color: colors.themeFgDefault)),
                        const SizedBox(height: 8),
                        Slider(
                            value: min(
                                player.position.inMilliseconds.toDouble(),
                                player.duration?.inMilliseconds.toDouble() ??
                                    0),
                            min: 0.0,
                            max:
                                player.duration?.inMilliseconds.toDouble() ?? 0,
                            onChangeStart: (v) {
                              setState(() {
                                player.pause();
                              });
                            },
                            onChanged: (v) {
                              setState(() {
                                player.seek(Duration(milliseconds: v.toInt()));
                              });
                            },
                            onChangeEnd: (v) {
                              setState(() {
                                player.play();
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
                            Expanded(
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Row(children: [
                                      IconButton(
                                          onPressed: () {
                                            // setState(() {
                                            // });
                                          },
                                          icon: const Icon(
                                              Icons.volume_up_outlined,
                                              size: 24)),
                                      Expanded(
                                          child: Slider(
                                              value: player.volume,
                                              min: 0.0,
                                              max: 1.0,
                                              onChanged: (v) {
                                                setState(() {
                                                  player.setVolume(v);
                                                });
                                              }))
                                    ]))),
                            MaterialButton(
                              onPressed: () {
                                setState(() {
                                  if (player.playerState.processingState ==
                                          ProcessingState.completed ||
                                      !player.playing) {
                                    if (player.position == player.duration) {
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
                              shape: const CircleBorder(),
                              child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: (player.playerState.processingState ==
                                              ProcessingState.completed ||
                                          !player.playing)
                                      ? const Icon(Icons.play_arrow_outlined,
                                          size: 32)
                                      : const Icon(Icons.pause_outlined,
                                          size: 32)),
                            ),
                            Expanded(
                                child: Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                        onPressed: () {
                                          // setState(() {
                                          // });
                                        },
                                        icon: const Icon(
                                            Icons.settings_outlined,
                                            size: 24)))),
                          ],
                        )
                      ])
                    ])));
  }
}
