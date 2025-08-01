const List<String> supportedImageTypesInFilePreview = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
];

const List<String> audioContentTypes = [
  'audio/aac',
  'audio/x-wav',
  'audio/ogg',
  'audio/x-flac',
  'audio/mpeg',
];

const List<String> documentContentTypes = [
  'application/json',
  'text/plain',
  'text/csv',
  'text/markdown',
  'text/xml',
  'application/xml',
  'text/javascript',
  'application/javascript',
  'text/css',
  'text/html',
  'text/x-python',
  'text/x-java',
  'text/x-c',
  'text/x-cpp',
  'text/x-csharp',
  'text/x-ruby',
  'text/x-go',
  'text/x-rust',
  'text/x-swift',
  'text/x-kotlin',
  'text/x-scala',
  'text/x-yaml',
  'application/x-yaml',
  'text/x-toml',
  'application/toml',
];

const List<String> pdfContentTypes = [
  'application/pdf',
];

// Maximum file size for document preview (10MB for text files)
const int documentPreviewMaxFileSize = 1024 * 1024 * 10;

const profileQueryMaxRetries = 6;

const String hasAcceptedCookiePolicyKey = 'hasAcceptedCookiePolicy';
