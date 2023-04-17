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
          fit: BoxFit.cover,
          height: double.maxFinite,
          width: double.maxFinite,
          image: MemoryImage((widget.state as FsEntryPreviewImage).imageBytes),
        );

      default:
        return VideoPlayerWidget(
          videoUrl: (widget.state as FsEntryPreviewVideo).previewUrl,
        );
    }
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerWidget({Key? key, required this.videoUrl}) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _videoPlayerController;
  late ChewieController _chewieController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _videoPlayerController = VideoPlayerController.network(widget.videoUrl);
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: false,
      looping: true,
      showControls: true,
      allowFullScreen: false,
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            errorMessage,
            style: ArDriveTypography.body.buttonXLargeRegular(
              color:
                  ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    debugPrint('Disposing video player');
    _videoPlayerController.dispose();
    _chewieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(widget.videoUrl),
      onVisibilityChanged: (VisibilityInfo info) {
        if (mounted) {
          setState(
            () {
              if (_videoPlayerController.value.isInitialized) {
                _isPlaying = info.visibleFraction > 0.5;
                _isPlaying
                    ? _videoPlayerController.play()
                    : _videoPlayerController.pause();
              }
            },
          );
        }
      },
      child: Chewie(
        controller: _chewieController,
      ),
    );
  }
}
