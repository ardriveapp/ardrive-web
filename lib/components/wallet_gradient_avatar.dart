import 'package:flutter/material.dart';

/// A deterministic, animated pixel-grid avatar derived from a wallet address.
///
/// Generates a symmetric 5x5 pixel pattern from the address hash, similar to
/// GitHub identicons. The pattern is horizontally mirrored so it resembles
/// a face/shield/icon that users can recognize at a glance.
///
/// A subtle breathing animation gently pulses the colors for a living quality.
class WalletGradientAvatar extends StatefulWidget {
  final String address;
  final double size;
  final Color? ringColor;

  const WalletGradientAvatar({
    super.key,
    required this.address,
    this.size = 34,
    this.ringColor,
  });

  @override
  State<WalletGradientAvatar> createState() => _WalletGradientAvatarState();
}

class _WalletGradientAvatarState extends State<WalletGradientAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _AvatarData.fromAddress(widget.address);

    final ringWidth = widget.size > 40 ? 2.5 : 2.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final avatar = ClipOval(
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _PixelAvatarPainter(
              data: data,
              breathe: _controller.value,
            ),
          ),
        );

        if (widget.ringColor == null) return avatar;

        return Container(
          width: widget.size + ringWidth * 2,
          height: widget.size + ringWidth * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.ringColor!,
              width: ringWidth,
            ),
          ),
          child: avatar,
        );
      },
    );
  }
}

/// Pre-computed avatar data derived from the wallet address.
class _AvatarData {
  /// 5x5 grid — true means filled, false means background.
  /// Only stores left half + center (3 cols × 5 rows = 15 values).
  /// Mirrored horizontally for the full 5x5.
  final List<bool> cells;

  /// Primary fill color.
  final HSLColor color1;

  /// Secondary fill color.
  final HSLColor color2;

  /// Background color.
  final HSLColor bgColor;

  _AvatarData({
    required this.cells,
    required this.color1,
    required this.color2,
    required this.bgColor,
  });

  factory _AvatarData.fromAddress(String address) {
    // Generate deterministic hash values from the address
    final bytes = <int>[];
    for (var i = 0; i < address.length; i++) {
      bytes.add(address.codeUnitAt(i));
    }

    // Simple hash function — mix char codes into hash values
    var h1 = 0;
    var h2 = 0;
    var h3 = 0;
    for (var i = 0; i < bytes.length; i++) {
      h1 = (h1 * 31 + bytes[i]) & 0x7FFFFFFF;
      h2 = (h2 * 37 + bytes[i]) & 0x7FFFFFFF;
      h3 = (h3 * 41 + bytes[i]) & 0x7FFFFFFF;
    }

    // Derive two hues that are visually distinct (at least 60° apart)
    final hue1 = (h1 % 360).toDouble();
    var hue2 = (h2 % 360).toDouble();
    if ((hue2 - hue1).abs() < 60) {
      hue2 = (hue1 + 120) % 360;
    }

    final color1 = HSLColor.fromAHSL(1.0, hue1, 0.65, 0.55);
    final color2 = HSLColor.fromAHSL(1.0, hue2, 0.60, 0.50);
    final bgColor = HSLColor.fromAHSL(1.0, hue1, 0.15, 0.15);

    // Generate 15 cell values (3 cols × 5 rows) for symmetric 5x5 grid
    final cells = <bool>[];
    for (var i = 0; i < 15; i++) {
      // Use different bits from the hash for each cell
      final bit = ((h3 >> (i % 30)) & 1) == 1;
      cells.add(bit);
    }

    // Ensure at least 6 cells are filled for visual weight
    var filled = cells.where((c) => c).length;
    if (filled < 6) {
      for (var i = 0; i < cells.length && filled < 6; i++) {
        if (!cells[i]) {
          cells[i] = true;
          filled++;
        }
      }
    }

    return _AvatarData(
      cells: cells,
      color1: color1,
      color2: color2,
      bgColor: bgColor,
    );
  }

  /// Get whether a cell at (row, col) in the 5x5 grid is filled.
  bool isFilled(int row, int col) {
    // Mirror: col 0↔4, col 1↔3, col 2 is center
    final mappedCol = col > 2 ? 4 - col : col;
    return cells[row * 3 + mappedCol];
  }

  /// Get the fill color for a cell (alternates between color1 and color2).
  HSLColor getCellColor(int row, int col) {
    return (row + col) % 2 == 0 ? color1 : color2;
  }
}

class _PixelAvatarPainter extends CustomPainter {
  final _AvatarData data;
  final double breathe; // 0.0 to 1.0

  _PixelAvatarPainter({
    required this.data,
    required this.breathe,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / 5;

    // Breathing effect: subtle lightness shift
    final breatheOffset = (breathe - 0.5) * 0.08;

    // Draw background
    final bgColor = data.bgColor
        .withLightness((data.bgColor.lightness + breatheOffset).clamp(0.1, 0.3))
        .toColor();
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = bgColor,
    );

    // Draw filled cells
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 5; col++) {
        if (!data.isFilled(row, col)) continue;

        final hsl = data.getCellColor(row, col);
        final color = hsl
            .withLightness(
                (hsl.lightness + breatheOffset).clamp(0.3, 0.75))
            .toColor();

        final rect = Rect.fromLTWH(
          col * cellSize,
          row * cellSize,
          cellSize,
          cellSize,
        );

        canvas.drawRect(rect, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelAvatarPainter oldDelegate) {
    return oldDelegate.breathe != breathe || oldDelegate.data != data;
  }
}
