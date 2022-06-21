import 'package:ardrive/utils/filesize.dart';
import 'package:test/test.dart';

void main() {
  group(
    'filesize returns the correct string interpretation for',
    () {
      test('10 as int', () {
        expect(filesize(10), '10 B');
      });

      test('10 as string', () {
        expect(filesize('10'), '10 B');
      });

      test('1024 as int', () {
        expect(filesize(1024), '1 KiB');
      });

      test('1024 as string', () {
        expect(filesize('1024'), '1 KiB');
      });

      test('1M as int', () {
        expect(filesize(1024 * 1024), '1 MiB');
      });

      test('1G as int', () {
        expect(filesize(1024 * 1024 * 1024), '1 GiB');
      });

      test('1T as int', () {
        expect(filesize(1024 * 1024 * 1024 * 1024), '1 TiB');
      });

      test('1P as int', () {
        expect(filesize(1024 * 1024 * 1024 * 1024 * 1024), '1 PiB');
      });

      test('Invalid Value', () {
        late ArgumentError exception;
        try {
          filesize('abc');
        } on ArgumentError catch (e) {
          exception = e;
        }
        expect(exception, isArgumentError);
      });
    },
  );
}
