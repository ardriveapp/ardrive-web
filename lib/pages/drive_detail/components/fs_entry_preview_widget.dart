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
        return Center(
            child: SizedBox(
                height: 24, width: 24, child: CircularProgressIndicator()));

      case FsEntryPreviewImage:
        return ExtendedImage.network(
          widget.state.previewUrl,
          fit: BoxFit.fitWidth,
          cache: true,
        );

      case FsEntryPreviewPrivateImage:
        return ExtendedImage.memory(
          (widget.state as FsEntryPreviewPrivateImage).imageBytes,
          fit: BoxFit.fitWidth,
        );

      default:
        return Container();
    }
  }
}
