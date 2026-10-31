import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// A drive is an archive box with a badge for its kind (Phil's pick, D2),
/// not the database cylinder it was.
void main() {
  test('drives draw the archive box glyphs', () {
    expect(ArDriveIcons.publicDrive().icon, ArDriveIconsData.drive_public);
    expect(ArDriveIcons.privateDrive().icon, ArDriveIconsData.drive_private);
    expect(ArDriveIcons.sharedDrive().icon, ArDriveIconsData.drive_shared);
  });

  test('the glyphs come from the ArDrive icon font', () {
    for (final icon in [
      ArDriveIconsData.drive_public,
      ArDriveIconsData.drive_private,
      ArDriveIconsData.drive_shared,
    ]) {
      expect(icon.fontFamily, 'ArDriveIcons');
      expect(icon.fontPackage, 'ardrive_ui');
    }
    expect(
      [
        ArDriveIconsData.drive_public.codePoint,
        ArDriveIconsData.drive_private.codePoint,
        ArDriveIconsData.drive_shared.codePoint,
      ],
      [0xe881, 0xe882, 0xe883],
    );
  });
}
