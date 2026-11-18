import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// A glyph drawn smaller than its box keeps its share when the box grows,
/// as in the phone's New menu, which draws its icons at 24.
void main() {
  test('scaledTo grows the glyph with the box', () {
    const icon = ArDriveIcon(
      icon: ArDriveIconsData.vector_2,
      size: 20,
      glyphSize: 16,
    );

    final scaled = icon.scaledTo(24);

    expect(scaled.size, 24);
    expect(scaled.glyphSize, closeTo(19.2, 0.001));
    expect(scaled.icon, icon.icon);
  });

  test('an icon with no glyph size of its own stays that way', () {
    const icon = ArDriveIcon(icon: ArDriveIconsData.vector_2, size: 20);

    expect(icon.scaledTo(24).glyphSize, isNull);
    expect(icon.scaledTo(24).size, 24);
  });
}
