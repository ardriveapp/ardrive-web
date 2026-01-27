/**
 * Entry point for bundling @ardrive/turbo-sdk for browser usage.
 *
 * This file re-exports the SDK functions needed by ArDrive web app.
 * The /web export is the browser-compatible version of the SDK.
 */

// Turbo SDK exports
export {
  TurboFactory,
  ARToTokenAmount,
  ARIOToTokenAmount,
  ETHToTokenAmount,
  SOLToTokenAmount,
  POLToTokenAmount,
  ArconnectSigner,
} from '@ardrive/turbo-sdk/web';

// InjectedEthereumSigner from @ar.io/sdk (used for ARIO on AO via ETH wallet)
export { InjectedEthereumSigner } from '@ar.io/sdk/web';
