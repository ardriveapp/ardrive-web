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
  'application/x.arweave-manifest+json',
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
  'message/rfc822',
];

const List<String> pdfContentTypes = [
  'application/pdf',
];

// Maximum file size for document preview (25MB for text files)
const int documentPreviewMaxFileSize = 1024 * 1024 * 25;

const profileQueryMaxRetries = 6;

const String hasAcceptedCookiePolicyKey = 'hasAcceptedCookiePolicy';

/// Default Arweave GraphQL gateway base URL. Used as fallback when config has no
/// gateway and for any hardcoded arweave.net references.
const String graphqlGateway = 'https://arweave.net';

/// Default Arweave ARNS resolver base URL (e.g. name.arweave.net). Use for
/// ARNS resolver or gateway host references.
const String arnsResolverUrl = graphqlGateway;

/// Arweave.net host for building resolver URLs (e.g. ao.arweave.net, arfs.arweave.net).
const String arweaveNetHost = 'arweave.net';

/// Builds https://<name>.arweave.net from ARNS resolver name [name].
String resolveArnsNameUrl(String name) =>
    'https://$name.$arweaveNetHost';
