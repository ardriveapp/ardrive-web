/// Unified cache for wallet signers to avoid repeated signature requests.
///
/// This is critical for UX - users should only need to sign ONE message per
/// session, not multiple times.
library wallet_signer_cache;

export 'implementations/wallet_signer_cache_stub.dart'
    if (dart.library.html) 'implementations/wallet_signer_cache_web.dart';
