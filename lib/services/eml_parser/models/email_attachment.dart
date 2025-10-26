import 'dart:typed_data';
import 'dart:convert';
import 'package:equatable/equatable.dart';

class EmailAttachment extends Equatable {
  final String filename;
  final String contentType;
  final int size;
  final String id;
  final Uint8List? data;

  const EmailAttachment({
    required this.filename,
    required this.contentType,
    required this.size,
    required this.id,
    this.data,
  });

  /// Create from JS object
  factory EmailAttachment.fromJS(Map<String, dynamic> json) {
    Uint8List? bytes;
    if (json['data'] != null && json['data'].toString().isNotEmpty) {
      try {
        bytes = base64Decode(json['data']);
      } catch (e) {
        // Handle decode error
        bytes = null;
      }
    }

    return EmailAttachment(
      filename: json['filename']?.toString() ?? 'unknown',
      contentType: json['contentType']?.toString() ?? 'application/octet-stream',
      size: (json['size'] as num?)?.toInt() ?? 0,
      id: json['id']?.toString() ?? '',
      data: bytes,
    );
  }

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Get just the MIME type without parameters (e.g., "image/png" from "image/png; name=file.png")
  String get mimeType {
    final semicolonIndex = contentType.indexOf(';');
    if (semicolonIndex > 0) {
      return contentType.substring(0, semicolonIndex).trim();
    }
    return contentType.trim();
  }

  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isVideo => mimeType.startsWith('video/');

  bool get isTextFile {
    // Check if it's a text-based MIME type
    if (mimeType.startsWith('text/')) return true;

    // Check for other text-based formats
    const textMimeTypes = [
      'application/json',
      'application/xml',
      'application/javascript',
      'application/x-yaml',
      'application/toml',
    ];

    return textMimeTypes.contains(mimeType);
  }

  bool get isPreviewable => isImage || isTextFile || isAudio || isVideo;

  @override
  List<Object?> get props => [filename, contentType, size, id, data];
}
