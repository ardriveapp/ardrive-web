// Inject Buffer as a global for browser compatibility
// IMPORTANT: Don't overwrite if already set by ario_sdk.min.js
// This ensures both bundles use the same Buffer implementation
import { Buffer } from 'buffer';
if (!globalThis.Buffer) {
  globalThis.Buffer = Buffer;
}
