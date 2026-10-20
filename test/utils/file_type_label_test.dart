import 'package:ardrive/utils/file_type_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String label(String contentType, String fileName) => fileTypeLabel(
        contentType: contentType,
        fileName: fileName,
        manifestLabel: 'Manifest',
      );

  group('fileTypeLabel', () {
    test('names a manifest in words, not by its content type', () {
      expect(
        label('application/x.arweave-manifest+json', 'site.json'),
        'Manifest',
      );
    });

    test('is the extension the preview leaves off the name', () {
      expect(label('text/plain', 'notes.txt'), 'TXT');
      expect(label('image/jpeg', 'photo.jpg'), 'JPG');
      expect(
        label(
          'application/vnd.openxmlformats-officedocument.'
              'wordprocessingml.document',
          'report.docx',
        ),
        'DOCX',
      );
    });

    test('falls back to a short content subtype with no extension', () {
      expect(label('image/png', 'screenshot'), 'PNG');
    });

    test('shows any other type as it is, in its own case', () {
      expect(
        label('application/vnd.ms-excel', 'export'),
        'application/vnd.ms-excel',
      );
    });
  });
}
