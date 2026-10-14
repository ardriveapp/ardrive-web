/// Granting a derived Arweave wallet permission to spend credits that live on
/// the wallet somebody signed in with.
library credit_sharing_service;

export 'implementations/credit_sharing_service_stub.dart'
    if (dart.library.html) 'implementations/credit_sharing_service_web.dart';
