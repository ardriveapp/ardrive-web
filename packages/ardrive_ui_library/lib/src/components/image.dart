import 'package:flutter/material.dart';

class ArDriveImage extends StatelessWidget {
  final ImageProvider image;
  final ImageProvider? placeholder;
  final double? height;
  final double? width;
  final BoxFit? fit;
  const ArDriveImage({
    super.key,
    required this.image,
    this.placeholder,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final imagePlaceholder = placeholder;
    if (imagePlaceholder != null) {
      return FadeInImage(
        placeholder: imagePlaceholder,
        fit: fit,
        image: image,
        height: height,
        width: width,
      );
    }
    return Image(
      fit: fit,
      image: image,
      height: height,
      width: width,
    );
  }
}
