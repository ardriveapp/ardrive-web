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
  VideoPlayerController? videoPlayerController;
  ChewieController? chewieController;

  @override
  void dispose() {
    if (videoPlayerController != null) {
      videoPlayerController?.dispose();
      chewieController?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.state.runtimeType) {
      case FsEntryPreviewImage:
        return Image(
          loadingBuilder: (context, child, loadingProgress) =>
              CircularProgressIndicator(),
          image: NetworkImage(widget.state.previewUrl),
        );
      case FsEntryPreviewVideo:
        videoPlayerController =
            VideoPlayerController.network(widget.state.previewUrl)
              ..initialize();

        chewieController = ChewieController(
          videoPlayerController: videoPlayerController!,
          autoPlay: true,
          looping: true,
        );
        return Chewie(
          controller: chewieController!,
        );
      default:
        return Container();
    }
  }
}
