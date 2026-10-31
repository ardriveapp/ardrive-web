import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every drive is one plain archive box, as Google Drive draws them; a kind
/// is said with a plain icon of its own (Phil's pick, B).
void main() {
  test('a drive is the plain archive box from the ArDrive font', () {
    final drive = ArDriveIcons.drive().icon;
    expect(drive, ArDriveIconsData.drive);
    expect(drive.codePoint, 0xe881);
    expect(drive.fontFamily, 'ArDriveIcons');
    expect(drive.fontPackage, 'ardrive_ui');
  });

  test('the kinds are plain lock, globe and people', () {
    expect(ArDriveIcons.privateDrive().icon, Icons.lock_outline);
    expect(ArDriveIcons.publicDrive().icon, Icons.public);
    expect(ArDriveIcons.sharedDrive().icon, Icons.people_outline);
  });
}
