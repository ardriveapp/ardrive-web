/// JavaScript interop for @ardrive/turbo-sdk
///
/// This file provides Dart bindings to the Turbo SDK loaded via index.html.
/// The SDK is loaded as a module and exposes functions on the window object.
library turbo_sdk;

// Export shared types
export 'turbo_sdk_types.dart';

// Export platform-specific implementation
export 'implementations/turbo_sdk_interop_stub.dart'
    if (dart.library.html) 'implementations/turbo_sdk_interop_web.dart';
