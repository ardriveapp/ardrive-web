import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyButton extends StatefulWidget {
  final String text;
  final double size;
  final bool showCopyText;
  final Widget? child;
  final int positionY;
  final int positionX;
  final Color? copyMessageColor;

  const CopyButton({
    super.key,
    required this.text,
    this.size = 20,
    this.showCopyText = true,
    this.child,
    this.positionY = 40,
    this.positionX = 20,
    this.copyMessageColor,
  });

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _showCheck = false;
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    if (_overlayEntry != null && _overlayEntry!.mounted) {
      _overlayEntry?.remove();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.child != null) {
      return GestureDetector(
        onTap: _copy,
        child: HoverWidget(
          hoverScale: 1,
          child: widget.child!,
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: ArDriveIconButton(
        tooltip: _showCheck ? '' : appLocalizationsOf(context).copyTooltip,
        onPressed: _copy,
        icon: _showCheck
            ? ArDriveIcons.checkCirle(
                size: widget.size,
                color: ArDriveTheme.of(context)
                    .themeData
                    .colors
                    .themeSuccessDefault,
              )
            : ArDriveIcons.copy(size: widget.size),
      ),
    );
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    if (mounted) {
      if (_showCheck) {
        return;
      }

      setState(() {
        _showCheck = true;
        if (widget.showCopyText) {
          _overlayEntry = _createOverlayEntry(context);
          Overlay.of(context).insert(_overlayEntry!);
        }

        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) {
            return;
          }

          setState(() {
            _showCheck = false;
            if (_overlayEntry != null && _overlayEntry!.mounted) {
              _overlayEntry?.remove();
            }
          });
        });
      });
    }
  }

  OverlayEntry _createOverlayEntry(BuildContext parentContext) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset buttonPosition = button.localToGlobal(Offset.zero);
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return OverlayEntry(
      builder: (context) => Positioned(
        left: buttonPosition.dx - widget.positionX,
        top: buttonPosition.dy - widget.positionY,
        child: Material(
          color: widget.copyMessageColor ?? colorTokens.containerL1,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Center(
              child: Text(
                'Copied!',
                style: typography.paragraphNormal(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}