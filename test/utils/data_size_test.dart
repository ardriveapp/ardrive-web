import 'package:ardrive/utils/data_size.dart';
import 'package:flutter_test/flutter_test.dart';

/// https://www.kylesconverter.com/data-storage/gibibits-to-bits
void main() {
  group('Testing KiB class', () {
    test('should return correct size', () {
      expect(KiB(1).size, 1024);
    });

    test('should return correct size', () {
      expect(KiB(150).size, 153600);
    });

    test('should return correct size', () {
      expect(KiB(15).size, 15360);
    });

    test('should return correct size', () {
      expect(KiB(25).size, 25600);
    });

    test('should return correct size', () {
      expect(KiB(0).size, 0);
    });
  });

  group('Testing MiB class', () {
    test('should return correct size', () {
      expect(MiB(200).size, 209715200);
    });

    test('should return correct size', () {
      expect(MiB(480).size, 503316480);
    });

    test('should return correct size', () {
      expect(KiB(15).size, 15360);
    });

    test('should return correct size', () {
      expect(MiB(1).size, KiB(1024).size);
    });

    test('should return correct size', () {
      expect(MiB(900).size, 943718400);
    });

    test('should return correct size', () {
      expect(MiB(0).size, 0);
    });
  });

  group('Testing GiB class', () {
    test('should return correct size', () {
      expect(GiB(1).size, 1073741824);
    });

    test('should return correct size', () {
      expect(GiB(15).size, 16106127360);
    });

    test('should return correct size', () {
      expect(GiB(25).size, 26843545600);
    });

    test('should return correct size', () {
      expect(GiB(1).size, MiB(1024).size);
    });

    test('should return correct size', () {
      expect(GiB(0).size, 0);
    });
  });
}
