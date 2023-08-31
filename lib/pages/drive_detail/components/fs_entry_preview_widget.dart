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

  late Null Function() listener;
  // late ChewieController _chewieController;
  // bool _isPlaying = false;

  @override
  void initState() {
    logger.d('Initializing video player: ${widget.videoUrl}');
    super.initState();
    _videoPlayerController =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _videoPlayerController.initialize();

    listener = () {
      // print('buffer data:');
      // for (final bufferRange in _videoPlayerController.value.buffered) {
      //   print(bufferRange);
      // }
      setState(() {});
    };

    _videoPlayerController.addListener(listener);
    // _chewieController = ChewieController(
    //   videoPlayerController: _videoPlayerController,
    //   autoPlay: false,
    //   looping: true,
    //   showControls: true,
    //   allowFullScreen: true,
    //   aspectRatio: 1,
    //   errorBuilder: (context, errorMessage) {
    //     return Center(
    //       child: Text(
    //         errorMessage,
    //         style: ArDriveTypography.body.buttonXLargeRegular(
    //           color:
    //               ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
    //         ),
    //       ),
    // );
    // },
    // );
  }

  @override
  void dispose() {
    logger.d('Disposing video player');
    // _chewieController.videoPlayerController.dispose();
    // _chewieController.dispose();
    _videoPlayerController.removeListener(listener);
    _videoPlayerController.dispose();
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
                      child: VideoPlayer(_videoPlayerController))),
              const SizedBox(height: 8),
              Column(children: [
                Text(widget.filename,
                    style: ArDriveTypography.body
                        .smallBold700(color: colors.themeFgDefault)),
                const SizedBox(height: 4),
                const Text('metadata'),
                const SizedBox(height: 8),
                Slider(
                    value: videoValue.position.inSeconds.toDouble(),
                    min: 0.0,
                    max: videoValue.duration.inSeconds.toDouble(),
                    onChangeStart: (v) async {
                      await _videoPlayerController.pause();
                    },
                    onChanged: (v) async {
                      await _videoPlayerController
                          .seekTo(Duration(seconds: v.toInt()));
                    },
                    onChangeEnd: (v) async {
                      await _videoPlayerController
                          .seekTo(Duration(seconds: v.toInt()));
                      await _videoPlayerController.play();
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
                          final videoValue = _videoPlayerController.value;
                          final newPosition =
                              videoValue.position - const Duration(seconds: 15);
                          _videoPlayerController.seekTo(newPosition);
                        },
                        icon: const Icon(Icons.fast_rewind_outlined, size: 24)),
                    IconButton.filled(
                      onPressed: () async {
                        if (_videoPlayerController.value.isPlaying) {
                          await _videoPlayerController.pause();
                        } else {
                          await _videoPlayerController.play();
                        }
                      },
                      icon: _videoPlayerController.value.isPlaying
                          ? const Icon(Icons.pause_outlined, size: 24)
                          : const Icon(Icons.play_arrow_outlined, size: 24),
                    ),
                    IconButton(
                        onPressed: () {
                          final videoValue = _videoPlayerController.value;
                          final newPosition =
                              videoValue.position + const Duration(seconds: 15);

                          _videoPlayerController.seekTo(newPosition);
                        },
                        icon: const Icon(Icons.fast_forward_outlined, size: 24))
                  ],
                )
              ])
            ]))

        // Chewie(
        //   controller: _chewieController,
        // ),
        );
  }
}
