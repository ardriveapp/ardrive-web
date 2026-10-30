abstract class FileTypeHelper {
  static const List<String> _imageTypes = ['image/'];
  static const List<String> _audioTypes = ['audio/'];
  static const List<String> _videoTypes = ['video/'];

  static const List<String> _docTypes = [
    'text/',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/pdf',
  ];

  static const List<String> _codeTypes = [
    'text/html',
    'text/css',
    'text/javascript',
    'application/javascript',
    'application/json',
    'application/xml',
    'application/xhtml+xml',
    'text/x-c++src',
    'text/x-csrc',
    'text/x-diff',
    'text/x-go',
    'text/x-java',
    'text/x-kotlin',
    'text/x-markdown',
    'text/x-perl',
    'text/x-python',
    'text/x-rustsrc',
    'text/x-swift',
  ];

  static const List<String> _zipTypes = [
    'application/zip',
    'application/x-rar-compressed'
  ];

  static const List<String> _manifestTypes = [
    'application/x.arweave-manifest+json',
  ];

  static bool isImage(String contentType) {
    return _imageTypes.any((type) => contentType.startsWith(type));
  }

  static bool isAudio(String contentType) {
    return _audioTypes.any((type) => contentType.startsWith(type));
  }

  static bool isVideo(String contentType) {
    return _videoTypes.any((type) => contentType.startsWith(type));
  }

  static bool isDoc(String contentType) {
    return _docTypes.contains(contentType) || contentType.startsWith('text/');
  }

  /// JSON data, a wallet keyfile among it, with or without parameters
  /// (`; charset=utf-8`) and in its `+json` forms (`application/ld+json`).
  /// Not a manifest, which is JSON too but stands for the files it lists.
  static bool isJson(String contentType) {
    final type = contentType.split(';').first.trim().toLowerCase();
    if (isManifest(type)) return false;
    return type == 'application/json' ||
        type == 'text/json' ||
        type.endsWith('+json');
  }

  static bool isCode(String contentType) {
    return _codeTypes.any((type) => contentType.startsWith(type));
  }

  static bool isZip(String contentType) {
    return _zipTypes.contains(contentType);
  }

  static bool isManifest(String contentType) {
    return _manifestTypes.contains(contentType);
  }
}
