import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(ArDriveMonospace.resetForTesting);

  test('the face is read once, however often it is asked for', () async {
    var reads = 0;
    final real = ArDriveMonospace.readFont;
    ArDriveMonospace.readFont = () {
      reads++;
      return real();
    };

    await Future.wait([
      ArDriveMonospace.ensureLoaded(),
      ArDriveMonospace.ensureLoaded(),
    ]);
    await ArDriveMonospace.ensureLoaded();
    ArDriveTypographyNew.desktop.code();

    expect(reads, 1);
  });

  // The text stays in Wavehaus meanwhile; a later preview tries again.
  test('a failed load is tried again on the next request', () async {
    var reads = 0;
    ArDriveMonospace.readFont = () {
      reads++;
      return Future.error(Exception('offline'));
    };

    await ArDriveMonospace.ensureLoaded();
    await ArDriveMonospace.ensureLoaded();

    expect(reads, 2);
  });

  test('code() is Roboto Mono, falling back to Wavehaus while it loads', () {
    for (final typography in [
      ArDriveTypographyNew.desktop,
      ArDriveTypographyNew.mobile,
    ]) {
      final style = typography.code();
      expect(style.fontFamily, ArDriveMonospace.family);
      expect(style.fontFamilyFallback, ['packages/ardrive_ui/Wavehaus']);
    }
  });

  test('the face is bundled as an asset, not listed as a font', () async {
    final data = await rootBundle
        .load('packages/ardrive_ui/assets/fonts/mono/RobotoMono-Regular.ttf');
    expect(data.lengthInBytes, greaterThan(10000));

    final manifest =
        await rootBundle.loadString('FontManifest.json').catchError((_) => '');
    expect(manifest, isNot(contains('RobotoMono')));
  });
}
