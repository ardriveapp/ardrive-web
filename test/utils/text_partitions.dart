import 'package:ardrive/utils/text_partitions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextPartitions class', () {
    final partitionsJA =
        TextPartitions(wholeText: '利用規約と ArDrive の プライバシーポリシーに同意します');
    final partitionsEN = TextPartitions(
        wholeText:
            'I agree to the ArDrive terms of service and privacy policy');

    test('throws if constructed with an empty string', () {
      expect(
        () => TextPartitions(wholeText: ''),
        throwsException,
      );
    });

    test('throws if atempting to set an unrelated segment', () {
      expect(
        () => partitionsJA
            .setSegment('ArDrive terms of service and privacy policy'),
        throwsException,
      );
      expect(
        () => partitionsEN.setSegment('ArDrive の プライバシーポリシー'),
        throwsException,
      );
    });

    test('sucessfully sets a segment if it matches', () {
      partitionsJA.setSegment('ArDrive の プライバシーポリシー');
      partitionsEN.setSegment('ArDrive terms of service and privacy policy');
      expect(partitionsJA.amount, 3);
      expect(partitionsEN.amount, 2);
    });

    test('throws if trying to get a unexistant segment', () {
      expect(
        () => partitionsJA.getSegment(4),
        throwsException,
      );
      expect(
        () => partitionsEN.getSegment(3),
        throwsException,
      );
    });

    test('sucessfully gets a segment if it exists', () {
      expect(
        partitionsJA.getSegment(0),
        '利用規約と ',
      );
      expect(
        partitionsJA.getSegment(1),
        'ArDrive の プライバシーポリシー',
      );
      expect(
        partitionsJA.getSegment(2),
        'に同意します',
      );
      expect(
        partitionsEN.getSegment(0),
        'I agree to the ',
      );
      expect(
        partitionsEN.getSegment(1),
        'ArDrive terms of service and privacy policy',
      );
    });
  });
}
