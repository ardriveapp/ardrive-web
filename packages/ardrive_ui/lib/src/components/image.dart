import 'package:flutter/material.dart';

class ArDriveImage extends StatelessWidget {
  final ImageProvider image;
  final ImageProvider? placeholder;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final Color? color;
  final Animation<double>? opacity;
  final BlendMode? colorBlendMode;
  const ArDriveImage({
    super.key,
    required this.image,
    this.placeholder,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.color,
    this.opacity,
    this.colorBlendMode,
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
      color: color,
      fit: fit,
      image: image,
      height: height,
      width: width,
      filterQuality: FilterQuality.high,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
    );
  }
}
