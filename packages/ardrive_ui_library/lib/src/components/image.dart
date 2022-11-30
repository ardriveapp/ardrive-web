import 'package:flutter/material.dart';

class ArDriveImage extends StatelessWidget {
  final ImageProvider imageProvider;
  final bool showPlaceholder;
  const ArDriveImage({
    super.key,
    required this.imageProvider,
    this.showPlaceholder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Image(
      fit: BoxFit.contain,
      image: imageProvider,
    );
  }
}
