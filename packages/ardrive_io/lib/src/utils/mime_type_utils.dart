import 'package:file_saver/file_saver.dart';
import 'package:mime/mime.dart' as mime;

/// Matches all strings that ends with `.gz` or `.tgz` and has at least one character before that
///
/// We should remove this after [mime#66](dart-lang/mime#66) released.
final gZipRegExp = RegExp('.\\.(gz|tgz)\$');

const applicationGZip = 'application/gzip';

String? lookupMimeType(String path, {List<int>? headerBytes}) {
  final pathMatch = gZipRegExp.firstMatch(path);
  if (pathMatch != null) {
    return applicationGZip;
  }

  return mime.lookupMimeType(path, headerBytes: headerBytes);
}

String lookupMimeTypeWithDefaultType(String path, {List<int>? headerBytes}) {
  path = path.toLowerCase();

  return lookupMimeType(path, headerBytes: headerBytes) ?? octetStream;
}

/// This implementation is specific for `file_saver` package.
MimeType getMimeTypeFromString(String mimeType) {
  switch (mimeType) {
    case 'video/x-msvideo':
      return MimeType.AVI;
    case 'audio/aac':
      return MimeType.AAC;
    case 'image/bmp':
      return MimeType.BMP;
    case 'application/epub+zip':
      return MimeType.EPUB;
    case 'image/gif':
      return MimeType.GIF;
    case 'application/json':
      return MimeType.JSON;
    case 'video/mpeg':
      return MimeType.MPEG;
    case 'audio/mpeg':
      return MimeType.MP3;
    case 'image/jpeg':
      return MimeType.JPEG;
    case 'font/otf':
      return MimeType.OTF;
    case 'image/png':
      return MimeType.PNG;
    case 'application/vnd.oasis.opendocument.presentation':
      return MimeType.OPENDOCPRESENTATION;
    case 'application/vnd.oasis.opendocument.text':
      return MimeType.OPENDOCTEXT;
    case 'application/vnd.oasis.opendocument.spreadsheet':
      return MimeType.OPENDOCSHEETS;
    case 'application/pdf':
      return MimeType.PDF;
    case 'font/ttf':
      return MimeType.TTF;
    case 'application/zip':
      return MimeType.ZIP;
    case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
      return MimeType.MICROSOFTEXCEL;
    case 'application/vnd.openxmlformats-officedocument.presentationml.presentation':
      return MimeType.MICROSOFTPRESENTATION;
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      return MimeType.MICROSOFTWORD;
    case 'application/vnd.etsi.asic-e+zip':
      return MimeType.ASICE;
    case 'application/vnd.etsi.asic-s+zip':
      return MimeType.ASICS;
    case 'text/plain':
      return MimeType.TEXT;
    case 'text/csv':
      return MimeType.CSV;
    default:
      return MimeType.OTHER;
  }
}

const String octetStream = 'application/octet-stream';
