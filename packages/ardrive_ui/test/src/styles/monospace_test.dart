import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/painting.dart';
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

  // An address beside other things is given this width up front, so it
  // doesn't move when the face replaces the fallback.
  testWidgets('widthOf is the width Roboto Mono draws', (tester) async {
    await tester.runAsync(ArDriveMonospace.ensureLoaded);

    for (final text in [
      'abc123...xyz9',
      'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA'
    ]) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: ArDriveTypographyNew.desktop.code()),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = ArDriveMonospace.widthOf(text, 13);
      expect(painter.width, lessThan(width));
      expect(painter.width, greaterThan(width - 2));
    }
  });

  test('widthOf grows with the reader\'s text size', () {
    final plain = ArDriveMonospace.widthOf('abc123...xyz9', 12);
    final larger = ArDriveMonospace.widthOf('abc123...xyz9', 12,
        textScaler: const TextScaler.linear(1.5));
    expect(larger, greaterThan(plain * 1.4));
  });
}
