import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';

enum ArDriveButtonStyle { primary, secondary, tertiary }

class ArDriveButton extends StatefulWidget {
  const ArDriveButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.style = ArDriveButtonStyle.primary,
  });

  final String text;
  final Function() onPressed;
  final ArDriveButtonStyle style;

  @override
  State<ArDriveButton> createState() => _ArDriveButtonState();
}

class _ArDriveButtonState extends State<ArDriveButton> {
  @override
  Widget build(BuildContext context) {
    switch (widget.style) {
      case ArDriveButtonStyle.primary:
        return ElevatedButton(
          style: ButtonStyle(
            maximumSize: _maxSize,
            minimumSize: _minimumSize,
            shape: _shape,
            padding: _padding,
            alignment: Alignment.center,
          ),
          onPressed: widget.onPressed,
          child: Text(
            widget.text,
            style: ArDriveTypography.headline.headline5Bold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgOnAccent,
            ),
          ),
        );
      case ArDriveButtonStyle.secondary:
        return OutlinedButton(
          onPressed: widget.onPressed,
          style: ButtonStyle(
            maximumSize: _maxSize,
            minimumSize: _minimumSize,
            shape: _shapeOutlined,
            side: _borderSize,
            padding: _padding,
          ),
          child: Text(
            widget.text,
            style: ArDriveTypography.headline.headline5Bold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
          ),
        );
      case ArDriveButtonStyle.tertiary:
        return ArDriveTextButton(
          text: widget.text,
          onPressed: widget.onPressed,
        );
    }
  }

  MaterialStateProperty<OutlinedBorder> get _shape =>
      MaterialStateProperty.resolveWith<OutlinedBorder>(
        (Set<MaterialState> states) {
          return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          );
        },
      );
  MaterialStateProperty<OutlinedBorder> get _shapeOutlined =>
      MaterialStateProperty.resolveWith<OutlinedBorder>(
        (Set<MaterialState> states) {
          return RoundedRectangleBorder(
            side: BorderSide(
              width: 3,
              style: BorderStyle.solid,
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
            borderRadius: BorderRadius.circular(6),
          );
        },
      );
  MaterialStateProperty<BorderSide?> get _borderSize =>
      MaterialStateProperty.resolveWith<BorderSide?>(
        (Set<MaterialState> states) {
          return BorderSide(
            width: 1,
            style: BorderStyle.solid,
            color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
          );
        },
      );

  MaterialStateProperty<EdgeInsets> get _padding =>
      MaterialStateProperty.resolveWith<EdgeInsets>(
        (Set<MaterialState> states) {
          return const EdgeInsets.symmetric(vertical: 12, horizontal: 12);
        },
      );
  MaterialStateProperty<Size> get _maxSize =>
      MaterialStateProperty.resolveWith<Size>(
        (Set<MaterialState> states) {
          return const Size(368, 56);
        },
      );

  MaterialStateProperty<Size> get _minimumSize {
    late double width;
    if (MediaQuery.of(context).size.width * 0.8 > 368 + 16) {
      width = 368;
    } else {
      width = MediaQuery.of(context).size.width * 0.8;
    }
    return MaterialStateProperty.resolveWith<Size>(
      (Set<MaterialState> states) {
        return Size(width, 56);
      },
    );
  }
}

class ArDriveTextButton extends StatelessWidget {
  const ArDriveTextButton({
    super.key,
    required this.text,
    required this.onPressed,
  });
  final String text;
  final Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: ButtonStyle(overlayColor: _hoverColor),
      onPressed: onPressed,
      child: Text(
        text,
        style: ArDriveTypography.body.smallRegular().copyWith(
              decoration: TextDecoration.underline,
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
      ),
    );
  }

  MaterialStateProperty<Color?> get _hoverColor =>
      MaterialStateProperty.resolveWith<Color?>(
        (Set<MaterialState> states) {
          return Colors.transparent;
        },
      );
}
