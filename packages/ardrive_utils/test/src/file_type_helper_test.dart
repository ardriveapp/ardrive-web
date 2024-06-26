import 'package:ardrive_utils/src/file_type_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileTypeHelper', () {
    test('isImage returns true for image types', () {
      expect(FileTypeHelper.isImage('image/jpeg'), isTrue);
      expect(FileTypeHelper.isImage('image/png'), isTrue);
      expect(FileTypeHelper.isImage('image/gif'), isTrue);
    });

    test('isImage returns false for non-image types', () {
      expect(FileTypeHelper.isImage('text/plain'), isFalse);
      expect(FileTypeHelper.isImage('application/pdf'), isFalse);
      expect(FileTypeHelper.isImage('video/mp4'), isFalse);
    });

    test('isAudio returns true for audio types', () {
      expect(FileTypeHelper.isAudio('audio/mpeg'), isTrue);
      expect(FileTypeHelper.isAudio('audio/wav'), isTrue);
      expect(FileTypeHelper.isAudio('audio/aac'), isTrue);
    });

    test('isAudio returns false for non-audio types', () {
      expect(FileTypeHelper.isAudio('text/plain'), isFalse);
      expect(FileTypeHelper.isAudio('image/jpeg'), isFalse);
      expect(FileTypeHelper.isAudio('video/mp4'), isFalse);
    });

    test('isVideo returns true for video types', () {
      expect(FileTypeHelper.isVideo('video/mp4'), isTrue);
      expect(FileTypeHelper.isVideo('video/avi'), isTrue);
      expect(FileTypeHelper.isVideo('video/mpeg'), isTrue);
    });

    test('isVideo returns false for non-video types', () {
      expect(FileTypeHelper.isVideo('text/plain'), isFalse);
      expect(FileTypeHelper.isVideo('image/jpeg'), isFalse);
      expect(FileTypeHelper.isVideo('audio/mpeg'), isFalse);
    });

    test('isDoc returns true for doc types', () {
      expect(FileTypeHelper.isDoc('text/plain'), isTrue);
      expect(FileTypeHelper.isDoc('application/msword'), isTrue);
      expect(
          FileTypeHelper.isDoc(
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
          isTrue);
      expect(FileTypeHelper.isDoc('application/pdf'), isTrue);
    });

    test('isDoc returns false for non-doc types', () {
      expect(FileTypeHelper.isDoc('image/jpeg'), isFalse);
      expect(FileTypeHelper.isDoc('video/mp4'), isFalse);
      expect(FileTypeHelper.isDoc('audio/mpeg'), isFalse);
    });

    test('isCode returns true for code types', () {
      expect(FileTypeHelper.isCode('text/html'), isTrue);
      expect(FileTypeHelper.isCode('text/javascript'), isTrue);
      expect(FileTypeHelper.isCode('application/json'), isTrue);
      expect(FileTypeHelper.isCode('text/x-python'), isTrue);
      expect(FileTypeHelper.isCode('text/x-c++src'), isTrue);
      expect(FileTypeHelper.isCode('text/x-csrc'), isTrue);
      expect(FileTypeHelper.isCode('text/x-java'), isTrue);
    });

    test('isCode returns false for non-code types', () {
      expect(FileTypeHelper.isCode('image/jpeg'), isFalse);
      expect(FileTypeHelper.isCode('video/mp4'), isFalse);
      expect(FileTypeHelper.isCode('audio/mpeg'), isFalse);
      expect(FileTypeHelper.isCode('application/msword'), isFalse);
    });

    test('isZip returns true for zip types', () {
      expect(FileTypeHelper.isZip('application/zip'), isTrue);
      expect(FileTypeHelper.isZip('application/x-rar-compressed'), isTrue);
    });

    test('isZip returns false for non-zip types', () {
      expect(FileTypeHelper.isZip('image/jpeg'), isFalse);
      expect(FileTypeHelper.isZip('video/mp4'), isFalse);
      expect(FileTypeHelper.isZip('audio/mpeg'), isFalse);
    });
  });
}
