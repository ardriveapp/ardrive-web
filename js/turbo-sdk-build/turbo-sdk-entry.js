/**
 * Unified entry point for @ardrive/turbo-sdk and @ar.io/sdk for browser usage.
 *
 * This bundles BOTH SDKs together so they share the same Buffer polyfill,
 * avoiding type mismatches when passing signer objects to TurboFactory.
 *
 * This matches how turbo-app imports these SDKs.
 */

// Turbo SDK exports (including ArconnectSigner which turbo-sdk re-exports)
export {
  TurboFactory,
  ArconnectSigner,
  ARToTokenAmount,
  ARIOToTokenAmount,
  ETHToTokenAmount,
  SOLToTokenAmount,
  POLToTokenAmount,
  tokenToBaseMap,
} from '@ardrive/turbo-sdk/web';

// AR.IO SDK exports (InjectedEthereumSigner for ARIO via ETH wallets)
export {
  InjectedEthereumSigner,
} from '@ar.io/sdk/web';
