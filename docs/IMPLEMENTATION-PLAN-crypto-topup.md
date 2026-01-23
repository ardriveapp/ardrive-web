# Implementation Plan: Cryptocurrency Top-Up for ArDrive

## Executive Summary

This document provides a complete, end-to-end implementation plan for adding cryptocurrency top-up support to ArDrive Web. It addresses all UI/UX flows, edge cases, error states, and technical implementation details.

**Key Decisions:**
- **Platform**: Web only (desktop + mobile browser)
- **Feature Flag**: None - launch to all users
- **Analytics**: Use existing Sentry logging (no new analytics)
- **SDK**: Use @ardrive/turbo-sdk via JavaScript interop
- **Networks**: Dev branch → testnets (with mainnet toggle), staging/prod → mainnet

---

## Table of Contents

1. [Gap Analysis: PRD vs Implementation](#1-gap-analysis-prd-vs-implementation)
2. [Complete User Flow Matrix](#2-complete-user-flow-matrix)
3. [Technical Architecture](#3-technical-architecture)
4. [Implementation Tasks (Detailed)](#4-implementation-tasks-detailed)
5. [File-by-File Implementation Guide](#5-file-by-file-implementation-guide)
6. [Edge Cases & Error Handling Matrix](#6-edge-cases--error-handling-matrix)
7. [Testing Plan](#7-testing-plan)
8. [Rollout Plan](#8-rollout-plan)

---

## 1. Gap Analysis: PRD vs Implementation

### Gaps Identified and Resolutions

| # | Gap | Resolution |
|---|-----|------------|
| 1 | **ERC-20 approvals not documented** | SDK handles approvals internally via `topUpWithTokens()`. No frontend approval logic needed. Document this behavior. |
| 2 | **InjectedEthereumSigner complexity** | ARIO on AO from Ethereum wallet requires public key recovery from signature. Add dedicated flow with `arioAOViaEth` token type. |
| 3 | **Signer caching not specified** | Cache signer at module level with key `${walletType}_${address}_${chainId}`. Only request ONE signature per session. |
| 4 | **X402 probe-based pricing for Base-USDC** | Base-USDC uses special `/x402/data-item/signed` endpoint. Add separate pricing path. |
| 5 | **Balance refresh interval** | 5-minute auto-refresh, not real-time. Pause timer when modal closed. |
| 6 | **Account switch handling** | Added `CryptoTopupAccountChanged` event. Clear payment state, AO signature cache, return to token selection with warning. |
| 7 | **Transaction retry delay** | 3-second hardcoded wait before retry for block inclusion. Document in UI. |
| 8 | **Missing crypto token icons** | Need to add ETH, USDC, SOL, ARIO, Base chain icons. Create/source SVGs. |
| 9 | **Testnet configuration** | Dev uses testnets with mainnet toggle (ctrl+shift+q), staging/prod use mainnet. |
| 10 | **No "connecting" signature UX for ARIO** | Added AO Connect Signature screen (PRD Section 4) for Ethereum users signing ARIO on AO. |
| 11 | **Quote expiration is 5 min, not configurable** | Turbo quotes expire in 5 minutes. Timer must match this. |
| 12 | **Network add flow for Base** | Added Manual Network Switch screen (PRD Section 11) with `wallet_addEthereumChain` flow and manual instructions fallback. |
| 13 | **Gas + payment amount validation** | Added gas estimation to PRD (Amount Entry section). Validate `balance >= amount + gasEstimate` for native tokens. |
| 14 | **WalletConnect QR modal** | WalletConnect shows QR code modal for mobile wallets. Set modal z-index to 10000. |
| 15 | **Clipboard feedback** | Use existing `CopyButton` component for transaction ID copy. |
| 16 | **External link utility** | Use existing `openUrl()` for block explorer links. |
| 17 | **Price volatility not handled** | Added Price Volatility Warning screen (PRD Section 12). Show warning when price changes >5%. |
| 18 | **Concurrent session handling missing** | Added session lock via `localStorage` with cross-tab detection. Show warning when another tab is active. |
| 19 | **Input mode toggle missing** | Added `CryptoTopupInputModeChanged` event for USD/token input toggle. |
| 20 | **Missing testnet ARIO address** | **TODO**: Get testnet ARIO address from AR.IO team before Phase 1 begins. |
| 21 | **RainbowKit integration details** | Added WalletConnect project ID requirement and wallet SDK loading details to Phase 2.1. |
| 22 | **Solflare detection not explicit** | Added explicit Phantom/Solflare detection via `isPhantom` and `window.solflare`. |

---

## 2. Complete User Flow Matrix

### 2.1 Primary Flows

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CRYPTO TOP-UP FLOW MATRIX                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ENTRY: User clicks "Add Turbo Credits" button                              │
│                           │                                                  │
│                           ▼                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  MODAL OPENS: Payment Method Tabs                                    │   │
│  │  [ Credit Card ]  [ Cryptocurrency ]                                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                           │                                                  │
│           ┌───────────────┴───────────────┐                                 │
│           ▼                               ▼                                 │
│  ┌─────────────────┐           ┌─────────────────────────────────────┐     │
│  │ Credit Card Tab │           │ Cryptocurrency Tab                   │     │
│  │ (existing flow) │           │                                      │     │
│  └─────────────────┘           │  FLOW A: ARIO on AO (Arweave wallet) │     │
│                                │  FLOW B: Ethereum tokens (ETH/USDC)   │     │
│                                │  FLOW C: ARIO on Base (EVM)          │     │
│                                │  FLOW D: ARIO on AO via ETH wallet   │     │
│                                │          (arioAOViaEth token type)   │     │
│                                │  FLOW E: SOL (Solana wallet)         │     │
│                                └─────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Flow A: ARIO on AO (Native Arweave Wallet)

**Simplest flow - uses already-connected wallet**

```
Token Selection → Amount Entry → Confirmation → Processing → Success
      │                │              │              │           │
      │                │              │              │           │
   [Select         [Enter USD     [Review &      [Spinner    [Confetti
    ARIO on AO]     amount]        Confirm]       + txId]     + Done]
```

**States:**
1. `TokenSelection` - ARIO on AO highlighted as "Recommended"
2. `AmountEntry` - Shows Arweave wallet address, ARIO balance
3. `Confirmation` - No network switch needed
4. `Processing` - Instant to 3 min confirmation
5. `Success` - Credits added

**No wallet connection step needed** - uses existing `window.arweaveWallet`

---

### 2.3 Flow B: Ethereum Tokens (ETH L1, Base ETH, USDC)

```
Token Selection → Wallet Connection → Amount Entry → Confirmation → Processing → Success
      │                 │                  │              │              │           │
      │                 │                  │              │              │           │
   [Select          [MetaMask/         [Enter USD     [Review,       [Spinner    [Confetti
    ETH on Base]     Rainbow/etc]       amount]        switch net]    + txId]     + Done]
```

**Sub-states for Wallet Connection:**
- `WalletOptions` - Show MetaMask, Rainbow, WalletConnect, Coinbase options
- `WalletConnecting` - Spinner + "Approve in wallet"
- `WalletError` - Connection rejected/failed
- `WalletNotInstalled` - Extension not found, show install link

**Sub-states for Confirmation (Network Switch):**
- `CheckingNetwork` - Verify current chain ID
- `SwitchingNetwork` - Auto-switch in progress
- `NetworkSwitchFailed` - Manual instructions
- `AddingNetwork` - Adding Base network to wallet (if not present)
- `ReadyToSign` - Correct network, show "Confirm & Pay"

---

### 2.4 Flow C: ARIO on Base (EVM Token)

Same as Flow B, but:
- Token is ARIO (ERC-20 on Base)
- Contract: `0x138746adfA52909E5920def027f5a8dc1C7EfFb6`
- 6 decimals (like USDC)

---

### 2.5 Flow D: ARIO on AO (From Ethereum Wallet) - SPECIAL FLOW

**This is the complex flow requiring InjectedEthereumSigner**

```
Token Selection → Wallet Connection → CONNECT SIGNATURE → Amount Entry → Confirmation → Processing → Success
      │                 │                   │                  │              │              │           │
      │                 │                   │                  │              │              │           │
   [Select          [MetaMask/         [Sign message      [Enter USD     [Review &      [Spinner    [Confetti
    ARIO on AO       Rainbow/etc]       to derive          amount]        Confirm]       + txId]     + Done]
    + I have ETH                         public key]
    wallet]
```

**Extra step: Connect Signature**
- User must sign a message: "Sign this message to connect to ArDrive for ARIO payment"
- This derives their public key for AO data item signing
- Show clear explanation: "This signature allows your Ethereum wallet to interact with the AO network"
- **Cache this signature** - only ask once per session

**UI for Connect Signature:**
```
┌─────────────────────────────────────────────────────────────────┐
│                                                         [X]     │
│                                                                 │
│   Connect to AO Network                         (leadBold)      │
│                                                                 │
│   To pay with ARIO on AO using your Ethereum                   │
│   wallet, we need to establish a secure connection.            │
│                                                                 │
│   This requires a one-time signature (no transaction           │
│   or gas fee). This signature:                                 │
│   • Proves you own this wallet                                 │
│   • Enables interaction with the AO network                    │
│   • Is cached for your session                                 │
│                                                                 │
│   ─────────────────────────────────────────────────────────    │
│                                                                 │
│   Connected: 0x1234...5678                      (caption)       │
│                                                                 │
│   ─────────────────────────────────────────────────────────    │
│                                                                 │
│   Back                              [Sign & Connect]            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 2.6 Flow E: SOL (Solana Wallet)

```
Token Selection → Wallet Connection → Amount Entry → Confirmation → Processing → Success
      │                 │                  │              │              │           │
      │                 │                  │              │              │           │
   [Select          [Phantom/          [Enter USD     [Review &      [Spinner    [Confetti
    SOL]             Solflare]          amount]        Confirm]       + txId]     + Done]
```

**Sub-states for Wallet Connection:**
- `WalletOptions` - Show Phantom, Solflare options
- `WalletConnecting` - Spinner + "Approve in wallet"
- `WalletError` - Connection rejected/failed
- `WalletNotInstalled` - Extension not found, show install link

---

### 2.7 Pending Transaction Recovery Flow

**Entry: User has pending transaction from previous session**

```
Token Selection (with banner) → View Pending → Retry Processing → Success/Error
         │                           │                │               │
         │                           │                │               │
   [Banner: "You have          [Show txId,       [3s wait,       [Credits
    a pending tx"]              status]           resubmit]        added]
```

**Pending Transaction Banner:**
```
┌─────────────────────────────────────────────────────────────────┐
│  ⚠️ You have a pending transaction                              │
│  Transaction 0xabcd...ef12 is still processing.                │
│  [View Status]                               [Dismiss]         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Technical Architecture

### 3.1 Turbo SDK Integration via JavaScript Interop

**Approach**: Load `@ardrive/turbo-sdk/web` via `<script>` tag, access via JS interop.

**Why JS Interop (not Dart port):**
1. SDK already production-tested in turbo-app
2. Complex cryptographic operations (AO data items, Ethereum signing)
3. Maintains compatibility with SDK updates
4. Faster implementation

**Setup:**

```html
<!-- web/index.html -->
<!-- Pin to specific version for stability - update manually after testing -->
<script type="module">
  const TURBO_SDK_VERSION = '1.19.0';  // Pin version - check for updates monthly
  const SDK_URL = `https://unpkg.com/@ardrive/turbo-sdk@${TURBO_SDK_VERSION}/bundles/web.bundle.min.js`;

  try {
    const { TurboFactory, ARToTokenAmount, ARIOToTokenAmount, ETHToTokenAmount, SOLToTokenAmount } = await import(SDK_URL);
    window.TurboFactory = TurboFactory;
    window.ARToTokenAmount = ARToTokenAmount;
    window.ARIOToTokenAmount = ARIOToTokenAmount;
    window.ETHToTokenAmount = ETHToTokenAmount;
    window.SOLToTokenAmount = SOLToTokenAmount;
    window.TurboSDKLoaded = true;
  } catch (e) {
    console.error('Failed to load Turbo SDK:', e);
    window.TurboSDKLoaded = false;
    window.TurboSDKError = e.message;
  }
</script>
```

**SDK Load Failure Handling:**
- Check `window.TurboSDKLoaded` before showing Cryptocurrency tab
- If SDK failed to load, show error state: "Cryptocurrency payments are temporarily unavailable. Please use Credit Card or try again later."
- Log error to Sentry for monitoring

**Dart Interop:**

```dart
// lib/turbo/services/turbo_sdk_interop.dart
@JS('TurboFactory')
class TurboFactoryJS {
  external static dynamic unauthenticated(dynamic config);
  external static dynamic authenticated(dynamic config);
}

@JS('ARIOToTokenAmount')
external dynamic arIOToTokenAmount(num amount);

@JS('ETHToTokenAmount')
external dynamic ethToTokenAmount(num amount);

// etc.
```

### 3.2 Wallet Service Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WALLET SERVICE LAYER                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │
│  │  ArweaveWalletSvc   │  │  EthereumWalletSvc  │  │   SolanaWalletSvc   │ │
│  │  (existing)         │  │  (new)              │  │   (new)             │ │
│  ├─────────────────────┤  ├─────────────────────┤  ├─────────────────────┤ │
│  │ • getAddress()      │  │ • connect()         │  │ • connect()         │ │
│  │ • signDataItem()    │  │ • disconnect()      │  │ • disconnect()      │ │
│  │ • getBalance()      │  │ • getAddress()      │  │ • getAddress()      │ │
│  │                     │  │ • getChainId()      │  │ • getBalance()      │ │
│  │                     │  │ • switchNetwork()   │  │ • signTransaction() │ │
│  │                     │  │ • addNetwork()      │  │                     │ │
│  │                     │  │ • getBalance()      │  │                     │ │
│  │                     │  │ • getSigner()       │  │                     │ │
│  │                     │  │ • onAccountChange() │  │                     │ │
│  │                     │  │ • onChainChange()   │  │                     │ │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘ │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     CryptoPaymentService                             │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ • getQuote(token, amount, promoCode?)                               │   │
│  │ • executePayment(token, quote, walletService)                       │   │
│  │ • submitTransaction(token, txId)                                     │   │
│  │ • getTokenBalance(token, address)                                    │   │
│  │ • getTurboWalletAddresses()                                          │   │
│  │ • validatePromoCode(code)                                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                  CryptoTransactionStorage                           │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ • savePending(tx)                                                    │   │
│  │ • getPending(arweaveAddress)                                         │   │
│  │ • removePending(txId)                                                │   │
│  │ • getAllPending()                                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 State Management (BLoC)

```dart
// Main flow orchestrator
CryptoTopupBloc
  ├── Events
  │   ├── CryptoTopupStarted
  │   ├── CryptoTopupTokenSelected(token)
  │   ├── CryptoTopupWalletConnectionRequested(walletType)
  │   ├── CryptoTopupWalletConnected(address)
  │   ├── CryptoTopupWalletConnectionFailed(error)
  │   ├── CryptoTopupWalletDisconnected
  │   ├── CryptoTopupAccountChanged(newAddress)  // Different from disconnect - wallet switched accounts
  │   ├── CryptoTopupAOConnectSignatureRequested  // For ARIO via ETH
  │   ├── CryptoTopupAOConnectSignatureCompleted(publicKey)
  │   ├── CryptoTopupAOConnectSignatureFailed(error)
  │   ├── CryptoTopupAmountChanged(amount, isUsd)
  │   ├── CryptoTopupInputModeChanged(isUsdMode)  // Toggle USD/token input
  │   ├── CryptoTopupPromoCodeSubmitted(code)  // Triggered by Apply button click
  │   ├── CryptoTopupPromoCodeCleared
  │   ├── CryptoTopupProceedToConfirmation
  │   ├── CryptoTopupNetworkSwitchRequested
  │   ├── CryptoTopupNetworkSwitchCompleted
  │   ├── CryptoTopupNetworkSwitchFailed(error)
  │   ├── CryptoTopupNetworkAddRequested  // Add network to wallet
  │   ├── CryptoTopupNetworkAddCompleted
  │   ├── CryptoTopupNetworkAddFailed(error)
  │   ├── CryptoTopupManualNetworkCheckRequested  // User clicked "I've Switched"
  │   ├── CryptoTopupPaymentConfirmed
  │   ├── CryptoTopupPaymentSucceeded(txId, credits)
  │   ├── CryptoTopupPaymentFailed(error, txId?)
  │   ├── CryptoTopupRetryTransaction(txId)
  │   ├── CryptoTopupBackPressed
  │   ├── CryptoTopupQuoteRefreshRequested
  │   ├── CryptoTopupQuoteRefreshed(newQuote)  // Internal - quote auto-refreshed
  │   ├── CryptoTopupPriceVolatilityAccepted  // User accepted price change >5%
  │   ├── CryptoTopupPriceVolatilityRejected  // User rejected, return to amount entry
  │   ├── CryptoTopupSessionExpired
  │   └── CryptoTopupConcurrentSessionDetected  // Another tab has active session
  │
  └── States
      ├── CryptoTopupInitial
      ├── CryptoTopupTokenSelection(balance, pendingTx?, ethAddress?, solAddress?, isLoadingBalances)
      ├── CryptoTopupConcurrentSessionWarning(otherTabState)  // Another tab has active session
      ├── CryptoTopupWalletConnection(token, walletType, isConnecting, error?)
      ├── CryptoTopupWalletNotInstalled(walletType, installUrl)
      ├── CryptoTopupAOConnectSignature(token, ethAddress, isSigningMessage, error?)
      ├── CryptoTopupAmountEntry(token, walletAddress, balance, quote?, isLoading, promoState, isUsdMode, gasEstimate?, error?)
      ├── CryptoTopupConfirmation(token, quote, fromAddress, toAddress, networkState, isProcessing, gasEstimate?)
      ├── CryptoTopupNetworkSwitch(token, currentChain, requiredChain, isAdding, isSwitching, showManualInstructions, error?)
      ├── CryptoTopupPriceVolatilityWarning(originalQuote, newQuote, percentChange)  // >5% price change
      ├── CryptoTopupProcessing(txId, token, estimatedTime)
      ├── CryptoTopupSuccess(txId, creditsAdded, newBalance, token)
      ├── CryptoTopupError(errorType, message, txId?, canRetry)
      ├── CryptoTopupAccountChangedWarning(oldAddress, newAddress)  // User switched accounts
      └── CryptoTopupSessionTimeout

// Wallet connection state (separate cubit per wallet type)
EthereumWalletCubit
  ├── EthereumWalletDisconnected
  ├── EthereumWalletConnecting(walletType)
  ├── EthereumWalletConnected(address, chainId, walletType)
  ├── EthereumWalletSwitchingNetwork
  └── EthereumWalletError(message)

SolanaWalletCubit
  ├── SolanaWalletDisconnected
  ├── SolanaWalletConnecting(walletType)
  ├── SolanaWalletConnected(address, walletType)
  └── SolanaWalletError(message)
```

### 3.4 Network Configuration

```dart
// lib/turbo/config/crypto_network_config.dart

class CryptoNetworkConfig {
  final bool isTestnet;

  CryptoNetworkConfig({required this.isTestnet});

  // Factory for current environment
  factory CryptoNetworkConfig.fromEnvironment(String environment) {
    // Dev uses testnet by default (can toggle via ctrl+shift+q)
    // Staging and prod use mainnet
    final isTestnet = environment == 'development';
    return CryptoNetworkConfig(isTestnet: isTestnet);
  }

  // Ethereum L1
  int get ethereumChainId => isTestnet ? 11155111 : 1; // Sepolia : Mainnet
  String get ethereumRpcUrl => isTestnet
    ? 'https://eth-sepolia.public.blastapi.io'
    : 'https://ethereum.publicnode.com';
  String get ethereumExplorerUrl => isTestnet
    ? 'https://sepolia.etherscan.io'
    : 'https://etherscan.io';

  // Base L2
  int get baseChainId => isTestnet ? 84532 : 8453; // Base Sepolia : Base Mainnet
  String get baseRpcUrl => isTestnet
    ? 'https://sepolia.base.org'
    : 'https://mainnet.base.org';
  String get baseExplorerUrl => isTestnet
    ? 'https://sepolia.basescan.org'
    : 'https://basescan.org';

  // Solana
  String get solanaRpcUrl => isTestnet
    ? 'https://api.devnet.solana.com'
    : 'https://api.mainnet-beta.solana.com';
  String get solanaExplorerUrl => isTestnet
    ? 'https://solscan.io?cluster=devnet'
    : 'https://solscan.io';

  // AO / Arweave (no testnet distinction)
  String get arweaveGatewayUrl => 'https://arweave.net';
  String get aoGatewayUrl => 'https://ao.arweave.net';

  // Contract addresses
  String get usdcBaseAddress => isTestnet
    ? '0x036CbD53842c5426634e7929541eC2318f3dCF7e' // Base Sepolia USDC
    : '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913'; // Base Mainnet USDC

  String get usdcEthAddress => isTestnet
    ? '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238' // Sepolia USDC
    : '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'; // Mainnet USDC

  String get arioBaseAddress => isTestnet
    ? '0x...' // TODO: Get testnet ARIO address
    : '0x138746adfA52909E5920def027f5a8dc1C7EfFb6'; // Base Mainnet ARIO

  // Turbo service URLs
  String get turboPaymentUrl => isTestnet
    ? 'https://payment.ardrive.dev'
    : 'https://payment.ardrive.io';

  String get turboUploadUrl => isTestnet
    ? 'https://upload.ardrive.dev'
    : 'https://upload.ardrive.io';
}
```

---

## 4. Implementation Tasks (Detailed)

### Phase 1: Foundation (8-10 tasks)

#### 1.1 Turbo SDK Integration
- [ ] Add Turbo SDK script tag to `web/index.html`
- [ ] Create `lib/turbo/services/turbo_sdk_interop.dart` with JS bindings
- [ ] Create wrapper class `TurboSDKService` for type-safe Dart calls
- [ ] Test SDK loading and basic calls in browser console

#### 1.2 Data Models
- [ ] Create `lib/turbo/topup/models/crypto_token.dart` - enum with 8 tokens:
  - `arioAO` - ARIO on AO (Arweave wallet)
  - `arioAOViaEth` - ARIO on AO (via Ethereum wallet, requires InjectedEthereumSigner)
  - `arioBase` - ARIO on Base L2
  - `sol` - SOL on Solana
  - `usdcBase` - USDC on Base L2
  - `ethBase` - ETH on Base L2
  - `usdcEth` - USDC on Ethereum L1
  - `ethL1` - ETH on Ethereum L1
- [ ] Create `lib/turbo/topup/models/crypto_quote.dart` - quote data class (with gasEstimateUsd field)
- [ ] Create `lib/turbo/topup/models/crypto_payment_result.dart` - result class
- [ ] Create `lib/turbo/topup/models/pending_transaction.dart` - for recovery
- [ ] Create `lib/turbo/topup/models/wallet_connection_state.dart` - wallet states
- [ ] Create `lib/turbo/topup/models/session_lock.dart` - for cross-tab session locking

#### 1.3 Network Configuration
- [ ] Create `lib/turbo/config/crypto_network_config.dart`
- [ ] Add testnet toggle to existing ctrl+shift+q debug menu
- [ ] Wire configuration to environment (dev/staging/prod)

#### 1.4 Local Storage for Recovery
- [ ] Create `lib/turbo/services/crypto_transaction_storage.dart`
- [ ] Use `shared_preferences` for persistence
- [ ] Implement save/get/remove/getAll methods
- [ ] Add cleanup for transactions older than 24 hours

### Phase 2: Wallet Services (6-8 tasks)

#### 2.1 Ethereum Wallet Service
- [ ] Create `lib/turbo/services/ethereum_wallet_service.dart`
- [ ] Implement JS interop for `window.ethereum`
- [ ] Implement `connect(walletType)` with wallet type selection:
  - MetaMask: Direct `window.ethereum` connection
  - Rainbow: Uses same provider API as MetaMask
  - WalletConnect: Requires WalletConnect project ID (add to config)
  - Coinbase Wallet: Uses Coinbase Wallet SDK
- [ ] Implement `disconnect()`
- [ ] Implement `getAddress()`, `getChainId()`
- [ ] Implement `switchNetwork(chainId)` with auto-add for Base
- [ ] Implement `addNetwork(networkParams)` via `wallet_addEthereumChain`
- [ ] Implement `getBalance(tokenAddress?)` for native + ERC-20
- [ ] Implement `estimateGas(txParams)` via `eth_estimateGas`
- [ ] Implement `getGasPrice()` via `eth_gasPrice`
- [ ] Implement `getSigner()` for transaction signing
- [ ] Add event listeners: `accountsChanged`, `chainChanged`, `disconnect`
- [ ] Handle multiple wallet detection (prefer user's last choice)

**RainbowKit / Wallet Connection Configuration:**
- Add WalletConnect project ID to environment config
- Load wallet SDKs via `<script>` tags in `web/index.html`
- Set modal z-index to 10000 to ensure overlay visibility
- Handle WalletConnect QR modal for mobile wallet connection

#### 2.2 Solana Wallet Service
- [ ] Create `lib/turbo/services/solana_wallet_service.dart`
- [ ] Implement JS interop for `window.solana` (Phantom) and `window.solflare`
- [ ] Detect Phantom via `window.solana?.isPhantom`
- [ ] Detect Solflare via `window.solflare`
- [ ] Handle multiple Solana wallets present (let user choose)
- [ ] Implement `connect()`, `disconnect()`
- [ ] Implement `getAddress()`
- [ ] Implement `getBalance()` via `connection.getBalance()`
- [ ] Implement `estimateTransactionFee()` via `getRecentPrioritizationFees`
- [ ] Implement `signTransaction()` or `signAndSendTransaction()`
- [ ] Add disconnect listener

#### 2.3 Signer Caching (Critical for UX)
- [ ] Create `lib/turbo/services/ethereum_signer_cache.dart`
- [ ] Cache `InjectedEthereumSigner` at module level
- [ ] Cache public key recovery (AO connect signature)
- [ ] Clear cache on account change or disconnect
- [ ] Ensure only ONE signature request per session

### Phase 3: Payment Service (5-6 tasks)

#### 3.1 Crypto Payment Service
- [ ] Create `lib/turbo/services/crypto_payment_service.dart`
- [ ] Implement `getQuote(token, amount, promoCode?)`
- [ ] Implement `getTurboWalletAddresses()` via `/info` endpoint
- [ ] Implement `validatePromoCode(code, token, amount)`
- [ ] Implement `submitTransaction(token, txId)` for retry

#### 3.2 Payment Execution
- [ ] Implement `executePayment()` for each token type:
  - [ ] ARIO on AO (ArconnectSigner)
  - [ ] ARIO on AO via Ethereum (InjectedEthereumSigner)
  - [ ] ARIO on Base (walletAdapter)
  - [ ] ETH on Base (walletAdapter)
  - [ ] ETH on L1 (walletAdapter)
  - [ ] USDC on Base (walletAdapter)
  - [ ] USDC on L1 (walletAdapter)
  - [ ] SOL (walletAdapter)

#### 3.3 Balance Fetching
- [ ] Implement token balance fetching (via wallet services):
  - [ ] ARIO on AO: Use ar.io SDK `ARIO.init().getBalance()`
  - [ ] ETH (native): Via EthereumWalletService `getBalance()`
  - [ ] USDC/ARIO on EVM: Via EthereumWalletService `getBalance(tokenAddress)`
  - [ ] SOL: Via SolanaWalletService `getBalance()`
- [ ] Implement 5-minute auto-refresh timer for balances (pause when modal closed)

#### 3.4 Gas Estimation
- [ ] Implement gas estimation per chain:
  - [ ] EVM chains: `eth_estimateGas` + `eth_gasPrice` → convert to USD
  - [ ] Solana: `getRecentPrioritizationFees` + base fee → convert to USD
  - [ ] ARIO on AO: No gas (return 0)
- [ ] Cache gas estimates for 30 seconds (prices don't change that fast)
- [ ] Show "~$X.XX" format in UI, update on quote refresh

### Phase 4: BLoC Implementation (4-5 tasks)

#### 4.1 CryptoTopupBloc
- [ ] Create `lib/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart`
- [ ] Implement all events and state transitions
- [ ] Wire to wallet services and payment service
- [ ] Handle 25-minute session timeout
- [ ] Handle quote expiration (5 min) with auto-refresh

#### 4.2 Wallet Cubits
- [ ] Create `lib/turbo/topup/blocs/ethereum_wallet/ethereum_wallet_cubit.dart`
- [ ] Create `lib/turbo/topup/blocs/solana_wallet/solana_wallet_cubit.dart`
- [ ] Wire account change listeners to clear payment state

#### 4.3 Integration with Existing Flow
- [ ] Modify `showTurboTopupModal()` to support tab switching
- [ ] Ensure Credit Card flow remains unchanged
- [ ] Share `TurboSessionManager` between flows

### Phase 5: UI Components (12-15 tasks)

#### 5.1 Shared Components
- [ ] Create `lib/turbo/topup/views/components/payment_method_tabs.dart`
- [ ] Create `lib/turbo/topup/views/components/token_card.dart`
- [ ] Create `lib/turbo/topup/views/components/wallet_option_card.dart`
- [ ] Create `lib/turbo/topup/views/components/crypto_summary_card.dart`
- [ ] Create `lib/turbo/topup/views/components/connected_wallet_card.dart`
- [ ] Create `lib/turbo/topup/views/components/transaction_status_card.dart`
- [ ] Create `lib/turbo/topup/views/components/pending_transaction_banner.dart`

#### 5.2 Main Views
- [ ] Create `lib/turbo/topup/views/crypto/crypto_topup_tab.dart` - main container
- [ ] Create `lib/turbo/topup/views/crypto/token_selection_view.dart`
- [ ] Create `lib/turbo/topup/views/crypto/ethereum_wallet_connection_view.dart`
- [ ] Create `lib/turbo/topup/views/crypto/solana_wallet_connection_view.dart`
- [ ] Create `lib/turbo/topup/views/crypto/ao_connect_signature_view.dart` (ARIO via ETH)
- [ ] Create `lib/turbo/topup/views/crypto/crypto_amount_entry_view.dart`
- [ ] Create `lib/turbo/topup/views/crypto/crypto_confirmation_view.dart`
- [ ] Create `lib/turbo/topup/views/crypto/crypto_processing_view.dart`
- [ ] Create `lib/turbo/topup/views/crypto/crypto_success_view.dart`
- [ ] Create `lib/turbo/topup/views/crypto/crypto_error_view.dart`
- [ ] Create `lib/turbo/topup/views/crypto/network_switch_view.dart`

#### 5.3 Assets
- [ ] Add `assets/images/icons/eth_logo.svg`
- [ ] Add `assets/images/icons/usdc_logo.svg`
- [ ] Add `assets/images/icons/sol_logo.svg`
- [ ] Add `assets/images/icons/ario_logo.svg`
- [ ] Add `assets/images/icons/base_chain_logo.svg`
- [ ] Add `assets/images/icons/metamask_logo.svg`
- [ ] Add `assets/images/icons/rainbow_logo.svg`
- [ ] Add `assets/images/icons/walletconnect_logo.svg`
- [ ] Add `assets/images/icons/coinbase_wallet_logo.svg`
- [ ] Add `assets/images/icons/phantom_logo.svg`
- [ ] Add `assets/images/icons/solflare_logo.svg`
- [ ] Update `pubspec.yaml` assets section

### Phase 6: Localization (1-2 tasks)

- [ ] Add all localization keys to `lib/l10n/app_en.arb`
- [ ] Generate localization files with `flutter gen-l10n`

### Phase 7: Testing (5-7 tasks)

#### 7.1 Unit Tests
- [ ] Test `CryptoTopupBloc` state transitions
- [ ] Test `CryptoPaymentService` with mocked SDK
- [ ] Test `EthereumWalletService` with mocked `window.ethereum`
- [ ] Test `SolanaWalletService` with mocked `window.solana`
- [ ] Test `CryptoTransactionStorage` persistence

#### 7.2 Integration Tests
- [ ] Test full ARIO on AO flow (requires Arweave wallet)
- [ ] Test full ETH on Base flow (requires MetaMask + testnet)
- [ ] Test full SOL flow (requires Phantom + devnet)
- [ ] Test pending transaction recovery flow

#### 7.3 Manual Testing Checklist
- [ ] Create comprehensive manual test checklist (see Section 7)

### Phase 8: Polish & Documentation (3-4 tasks)

- [ ] Add loading shimmer for balance/quote fetching (use existing `ArDriveShimmer`)
- [ ] Ensure all animations match existing flow (300ms transitions)
- [ ] Verify mobile browser layouts (min-width 320px)
- [ ] Update CLAUDE.md with new architecture
- [ ] Add inline code documentation

**Accessibility:**
- [ ] Ensure all buttons/inputs have proper focus states
- [ ] Add semantic labels for screen readers (wallet addresses, token amounts)
- [ ] Support keyboard navigation (Tab through token cards, Enter to select)
- [ ] Test with VoiceOver/NVDA

**Theming:**
- [ ] Verify all colors use semantic theme tokens (no hardcoded colors)
- [ ] Test in both light and dark modes
- [ ] Ensure contrast ratios meet WCAG AA standards

---

## 5. File-by-File Implementation Guide

### New Files to Create

```
lib/turbo/
├── config/
│   └── crypto_network_config.dart          # Network URLs, chain IDs, contract addresses
│
├── services/
│   ├── turbo_sdk_interop.dart              # JS interop for @ardrive/turbo-sdk
│   ├── turbo_sdk_service.dart              # Type-safe Dart wrapper
│   ├── ethereum_wallet_service.dart        # Ethereum wallet operations
│   ├── ethereum_signer_cache.dart          # Signer caching for UX
│   ├── solana_wallet_service.dart          # Solana wallet operations
│   ├── crypto_payment_service.dart         # Quote, execute, retry
│   └── crypto_transaction_storage.dart     # Pending tx persistence
│
├── topup/
│   ├── blocs/
│   │   ├── crypto_topup/
│   │   │   ├── crypto_topup_bloc.dart
│   │   │   ├── crypto_topup_event.dart
│   │   │   └── crypto_topup_state.dart
│   │   ├── ethereum_wallet/
│   │   │   ├── ethereum_wallet_cubit.dart
│   │   │   └── ethereum_wallet_state.dart
│   │   └── solana_wallet/
│   │       ├── solana_wallet_cubit.dart
│   │       └── solana_wallet_state.dart
│   │
│   ├── models/
│   │   ├── crypto_token.dart
│   │   ├── crypto_quote.dart
│   │   ├── crypto_payment_result.dart
│   │   ├── pending_transaction.dart
│   │   ├── wallet_connection_state.dart
│   │   └── session_lock.dart               # Cross-tab session locking
│   │
│   └── views/
│       ├── crypto/
│       │   ├── crypto_topup_tab.dart
│       │   ├── token_selection_view.dart
│       │   ├── ethereum_wallet_connection_view.dart
│       │   ├── solana_wallet_connection_view.dart
│       │   ├── ao_connect_signature_view.dart
│       │   ├── crypto_amount_entry_view.dart
│       │   ├── crypto_confirmation_view.dart
│       │   ├── crypto_processing_view.dart
│       │   ├── crypto_success_view.dart
│       │   ├── crypto_error_view.dart
│       │   ├── network_switch_view.dart
│       │   ├── manual_network_switch_view.dart  # Manual switch instructions
│       │   ├── price_volatility_warning_view.dart  # >5% price change warning
│       │   ├── concurrent_session_warning_view.dart  # Cross-tab lock warning
│       │   └── account_changed_warning_view.dart  # Account switch warning
│       │
│       └── components/
│           ├── payment_method_tabs.dart
│           ├── token_card.dart
│           ├── wallet_option_card.dart
│           ├── crypto_summary_card.dart
│           ├── connected_wallet_card.dart
│           ├── transaction_status_card.dart
│           ├── pending_transaction_banner.dart
│           ├── gas_estimate_row.dart           # Network fee display
│           └── network_params_card.dart        # Manual network add params

assets/images/icons/
├── eth_logo.svg
├── usdc_logo.svg
├── sol_logo.svg
├── ario_logo.svg
├── base_chain_logo.svg
├── metamask_logo.svg
├── rainbow_logo.svg
├── walletconnect_logo.svg
├── coinbase_wallet_logo.svg
├── phantom_logo.svg
└── solflare_logo.svg

web/
└── index.html                              # Add Turbo SDK script tag

test/turbo/
├── blocs/
│   └── crypto_topup_bloc_test.dart
├── services/
│   ├── crypto_payment_service_test.dart
│   ├── ethereum_wallet_service_test.dart
│   └── solana_wallet_service_test.dart
└── test_utils/
    ├── mock_turbo_sdk.dart
    ├── mock_ethereum_wallet.dart
    └── mock_solana_wallet.dart
```

### Files to Modify

```
lib/turbo/topup/views/topup_modal.dart
  - Add PaymentMethodTabs at top
  - Conditionally render Credit Card or Crypto tab content
  - Wire CryptoTopupBloc

lib/components/top_up_dialog.dart
  - No changes needed (entry point remains same)

lib/utils/dependency_injection_utils.dart
  - Add CryptoPaymentService
  - Add EthereumWalletService
  - Add SolanaWalletService
  - Add CryptoTransactionStorage

lib/services/config/app_config.dart
  - Add crypto-related config fields (if needed beyond CryptoNetworkConfig)

lib/l10n/app_en.arb
  - Add all new localization keys

pubspec.yaml
  - Add new asset paths

web/index.html
  - Add Turbo SDK script import
```

---

## 6. Edge Cases & Error Handling Matrix

### 6.1 Wallet Connection Errors

| Scenario | Detection | User Message | Action |
|----------|-----------|--------------|--------|
| Extension not installed | `window.ethereum === undefined` | "MetaMask not detected. Install the extension to continue." | Show install link |
| User rejected connection | Error code 4001 | "Connection cancelled. Please try again if you want to proceed." | Show "Try Again" |
| Connection timeout | No response after 30s | "Connection timed out. Please try again." | Show "Try Again" |
| Multiple wallets conflict | RainbowKit handles | N/A - RainbowKit shows selector | N/A |
| Wallet locked | `eth_accounts` returns [] | "Wallet is locked. Please unlock and try again." | Show "Try Again" |

### 6.2 Network Errors

| Scenario | Detection | User Message | Action |
|----------|-----------|--------------|--------|
| Wrong network | `chainId !== requiredChainId` | "Please switch to Base network to continue." | Auto-switch or manual instructions |
| Network switch rejected | Error code 4001 | "Network switch cancelled. Please switch manually in your wallet." | Show manual instructions |
| Network not in wallet | Error code 4902 | "Adding Base network to your wallet..." | Auto-add via `wallet_addEthereumChain` |
| Add network failed | Error from `wallet_addEthereumChain` | "Could not add Base network. Please add it manually." | Show manual instructions with params |
| RPC error | Network fetch fails | "Could not connect to the network. Please try again." | Show "Try Again" |

### 6.3 Payment Errors

| Scenario | Detection | User Message | Action |
|----------|-----------|--------------|--------|
| Insufficient balance | Balance < amount | "Insufficient {TOKEN} balance. You have {BALANCE}." | Disable Continue button |
| Insufficient gas | `INSUFFICIENT_FUNDS` error | "Insufficient funds for gas. You need {TOKEN} for both payment and fees." | Show required total |
| User rejected tx | Error code 4001 | "Transaction cancelled." | Show "Try Again" |
| Gas estimation failed | Error includes "gas" | "Could not estimate gas. Please try again." | Show "Try Again" |
| Transaction failed on-chain | Receipt status 0 | "Transaction failed on the blockchain." | Show "Try Again" + tx link |
| Transaction stuck/pending | No receipt after timeout | "Transaction pending. Check status on block explorer." | Show tx link + "Retry Processing" |
| Quote expired | `quote.expiresAt < now` | "Quote expired. Getting new quote..." | Auto-refresh quote |
| Promo code invalid | 400 from validate endpoint | "Promo code is invalid or expired." | Clear promo field |
| Rate limit | 429 response | "Too many requests. Please wait a moment." | Disable buttons briefly |

### 6.4 Session & State Errors

| Scenario | Detection | User Message | Action |
|----------|-----------|--------------|--------|
| Session expired (25 min) | TurboSessionManager timeout | "Session expired for security. Please start again." | Reset to token selection |
| Wallet disconnected mid-flow | Account change to null | "Wallet disconnected. Please reconnect." | Show "Reconnect" button |
| Account changed mid-flow | Account change to different address | "Account changed. Your payment details have been reset." | Show warning, reset flow, clear state, clear AO signature cache |
| Browser tab hidden | `visibilitychange` event | N/A (pause timers) | Resume on visibility |
| Modal closed during processing | User closes modal | Show toast: "Payment processing in background." | Continue polling, show notification on complete |
| Concurrent session in another tab | `localStorage` session lock exists | "You have a top-up in progress in another tab." | Show warning with "Cancel Other Session" or "Go to Other Tab" |
| Stale session lock | Lock timestamp > 30 minutes old | N/A (ignore stale lock) | Clear stale lock, proceed normally |
| Price changed >5% | `(newQuote - originalQuote) / originalQuote > 0.05` | "Price Changed: Original X credits, New Y credits (-Z%)" | Show warning modal, require user to accept or cancel |

### 6.5 Recovery Scenarios

| Scenario | Detection | User Message | Action |
|----------|-----------|--------------|--------|
| Pending tx from previous session | `CryptoTransactionStorage.getPending()` | "You have a pending transaction." | Show banner with "View Status" |
| Retry after failure | User clicks "Retry Processing" | "Waiting for confirmation (3s)..." | Wait 3s, call `submitFundTransaction` |
| Retry still pending | 404 from submitFundTransaction | "Transaction not confirmed yet. Please wait 1-2 min and try again." | Keep retry option |
| Retry success | 200 from submitFundTransaction | "Credits added!" | Navigate to success |
| Transaction older than 24h | `createdAt < now - 24h` | "This transaction has expired. Please contact support." | Clear pending, show support link |

---

## 7. Testing Plan

### 7.1 Unit Test Coverage

```dart
// crypto_topup_bloc_test.dart
group('CryptoTopupBloc', () {
  // Token Selection
  test('emits TokenSelection on started');
  test('includes pending transaction if exists');
  test('includes connected wallet addresses if available');

  // Wallet Connection
  test('emits WalletConnection when Ethereum token selected without wallet');
  test('skips WalletConnection when ARIO on AO selected');
  test('emits AmountEntry when wallet already connected');
  test('emits WalletNotInstalled when extension not found');
  test('emits error on connection failure');

  // AO Connect Signature
  test('emits AOConnectSignature for ARIO via Ethereum');
  test('caches signature, skips on subsequent selections');

  // Amount Entry
  test('fetches quote on amount change (debounced)');
  test('validates minimum amount');
  test('validates maximum amount');
  test('validates against wallet balance');
  test('applies promo code discount');
  test('refreshes quote on expiration');

  // Confirmation
  test('emits NetworkSwitch if wrong chain');
  test('emits Confirmation when ready');
  test('handles network switch success');
  test('handles network switch failure');
  test('shows manual switch instructions on repeated failure');

  // Network Add
  test('attempts wallet_addEthereumChain for missing network');
  test('shows manual add instructions on add failure');

  // Price Volatility
  test('detects >5% price change on quote refresh');
  test('emits PriceVolatilityWarning state');
  test('continues with new price on accept');
  test('returns to amount entry on reject');

  // Account Switch
  test('detects accountsChanged event');
  test('clears payment state on account change');
  test('clears AO signature cache on account change');
  test('emits AccountChangedWarning state');

  // Concurrent Sessions
  test('detects existing session lock');
  test('emits ConcurrentSessionWarning state');
  test('clears other session on user request');
  test('ignores stale locks (>30 min)');

  // Gas Estimation
  test('fetches gas estimate for EVM tokens');
  test('returns zero gas for ARIO on AO');
  test('validates balance includes gas for native tokens');

  // Payment
  test('emits Processing on payment start');
  test('emits Success on payment complete');
  test('emits Error on payment failure');
  test('stores pending transaction');
  test('removes pending transaction on success');

  // Recovery
  test('retries transaction with 3s delay');
  test('handles retry success');
  test('handles retry still pending');

  // Session
  test('emits SessionTimeout after 25 minutes');
  test('resets state on back pressed');
});
```

### 7.2 Integration Test Scenarios

| Test | Wallet | Network | Token | Expected |
|------|--------|---------|-------|----------|
| Happy path - ARIO AO | ArConnect | AO | ARIO | Success |
| Happy path - ARIO AO via ETH | MetaMask | AO | ARIO | AO signature, then success |
| Happy path - ETH Base | MetaMask | Base | ETH | Success |
| Happy path - USDC Base | MetaMask | Base | USDC | Success |
| Happy path - ARIO Base | MetaMask | Base | ARIO | Success |
| Happy path - SOL | Phantom | Solana Devnet | SOL | Success |
| Happy path - Solflare | Solflare | Solana Devnet | SOL | Success |
| Network switch | MetaMask (on ETH) | Base | USDC | Auto-switch, success |
| Add network | MetaMask (no Base) | Base | ETH | Add Base, success |
| Manual network switch | MetaMask (reject switch) | Base | USDC | Show manual instructions |
| Insufficient balance | MetaMask | Base | USDC | Error shown |
| Insufficient gas | MetaMask | Base | USDC | "Need ETH for gas" error |
| User reject connection | MetaMask | Base | ETH | Error, retry option |
| User reject transaction | MetaMask | Base | ETH | Error, retry option |
| Account switch mid-flow | MetaMask | Base | USDC | Warning, reset to token selection |
| Price volatility | Any | Any | Any | >5% change shows warning |
| Concurrent tabs | Any | Any | Any | Session lock warning |
| WalletConnect mobile | WalletConnect | Base | ETH | QR code flow, success |
| Quote refresh during input | MetaMask | Base | USDC | Auto-refresh, no interruption |
| Session timeout | Any | Any | Any | Timeout screen |
| Recovery flow | N/A | Any | Any | Retry success |

### 7.3 Manual Testing Checklist

#### Pre-Testing Setup
- [ ] Install MetaMask, Rainbow, Phantom, Solflare extensions
- [ ] Fund test wallets with testnet tokens
- [ ] Configure app to use testnet (dev environment)

#### Token Selection Screen
- [ ] Balance displays correctly
- [ ] All 8 tokens display with correct icons (including ARIO on AO via ETH)
- [ ] ARIO on AO shows "Recommended" badge
- [ ] ARIO on AO (via Ethereum wallet) shows "Requires one-time signature"
- [ ] Wallet requirement labels show correctly
- [ ] Pending transaction banner shows if applicable
- [ ] Concurrent session warning shows if applicable
- [ ] Token cards have hover state

#### Wallet Connection (Ethereum)
- [ ] MetaMask connects successfully
- [ ] Rainbow connects successfully
- [ ] WalletConnect shows QR modal
- [ ] Coinbase Wallet connects
- [ ] Connection rejection shows error
- [ ] "Not installed" state shows install link
- [ ] Back button works

#### Wallet Connection (Solana)
- [ ] Phantom connects successfully
- [ ] Solflare connects successfully
- [ ] Connection rejection shows error
- [ ] "Not installed" state shows install link
- [ ] Back button works

#### AO Connect Signature (ARIO via ETH)
- [ ] Explanation text is clear
- [ ] Signature request appears in wallet
- [ ] Successful signature proceeds to amount entry
- [ ] Rejected signature shows error
- [ ] Signature is cached (not requested again)

#### Amount Entry Screen
- [ ] Wallet address displays (truncated)
- [ ] Balance displays correctly
- [ ] Preset buttons work ($10, $25, $50, $100)
- [ ] Custom amount input works
- [ ] Live pricing updates on typing (debounced)
- [ ] Minimum amount validation ($0.01)
- [ ] Maximum amount validation ($5,000)
- [ ] Insufficient balance error shows
- [ ] Promo code can be entered
- [ ] Valid promo code shows discount
- [ ] Invalid promo code shows error
- [ ] Quote timer counts down
- [ ] Quote auto-refreshes on expiry
- [ ] Continue button disabled when invalid
- [ ] Continue button enabled when valid
- [ ] Back button works

#### Confirmation Screen
- [ ] Summary shows all details correctly
- [ ] Token, amount, USD value, storage, fees
- [ ] Promo discount shows if applied
- [ ] From/To addresses display
- [ ] Network switch warning shows if needed
- [ ] Auto network switch works
- [ ] Manual network switch instructions work
- [ ] Quote timer continues
- [ ] Confirm button shows loading on click
- [ ] Back button works

#### Processing Screen
- [ ] Spinner displays
- [ ] Transaction ID displays
- [ ] Copy button works
- [ ] Explorer link opens correct URL
- [ ] Estimated time shows
- [ ] Close button shows toast message
- [ ] Processing continues in background

#### Success Screen
- [ ] Confetti animation plays
- [ ] Credits added amount shows
- [ ] New balance shows
- [ ] Transaction ID displays
- [ ] Explorer link works
- [ ] Done button closes modal
- [ ] Balance refreshes in header

#### Error Screens
- [ ] User rejection error shows retry option
- [ ] Network error shows retry option
- [ ] Insufficient funds error shows back only
- [ ] Insufficient gas error shows required amounts
- [ ] Transaction failed shows retry option
- [ ] Session timeout shows start over

#### Manual Network Switch Screen
- [ ] Instructions display correctly for Base network
- [ ] "Add Base Network" button attempts automatic add
- [ ] Manual add instructions show all required fields
- [ ] Copy buttons work for each field
- [ ] "I've Switched" re-checks network
- [ ] Correct network proceeds to confirmation
- [ ] Wrong network shows inline error

#### Price Volatility Warning
- [ ] Warning appears when price changes >5%
- [ ] Original and new credits shown
- [ ] Percentage difference shown in red
- [ ] "Accept New Price" continues with new quote
- [ ] "Cancel" returns to amount entry
- [ ] Warning only shown once per refresh

#### Account Switch Handling
- [ ] Account switch triggers warning message
- [ ] Payment state is cleared
- [ ] AO signature cache is cleared (if applicable)
- [ ] User returned to token selection
- [ ] New address shown correctly

#### Concurrent Session Handling
- [ ] Warning shows when another tab is active
- [ ] "Cancel Other Session" clears lock and proceeds
- [ ] "Go to Other Tab" closes modal
- [ ] Stale locks (>30 min) are ignored

#### Gas Estimation
- [ ] Network fee displays for EVM tokens
- [ ] Network fee updates with quote refresh
- [ ] "Insufficient gas" error shows when applicable
- [ ] No gas fee shown for ARIO on AO

#### Recovery Flow
- [ ] Pending transaction banner shows on reopen
- [ ] View Status shows transaction details
- [ ] Retry Processing waits 3 seconds
- [ ] Successful retry shows success
- [ ] Still pending shows wait message

#### Mobile Browser Testing
- [ ] Layout adapts to mobile width
- [ ] WalletConnect deep links work
- [ ] Touch interactions work
- [ ] Keyboard doesn't obscure input
- [ ] Scrolling works in modal

---

## 8. Rollout Plan

### 8.1 Development Phase

1. **Week 1-2**: Foundation + Wallet Services
   - Turbo SDK integration
   - Data models
   - Ethereum wallet service
   - Solana wallet service
   - Signer caching

2. **Week 3**: Payment Service + BLoC
   - Crypto payment service
   - CryptoTopupBloc implementation
   - Session management integration

3. **Week 4-5**: UI Implementation
   - All view components
   - Asset creation/sourcing
   - Localization

4. **Week 5-6**: Testing + Polish
   - Unit tests
   - Integration tests on testnets
   - Manual testing
   - Bug fixes

### 8.2 QA Phase

1. **Internal Testing** (1 week)
   - Full flow testing with real testnet tokens
   - Edge case validation
   - Mobile browser testing

2. **Staging Deployment** (1 week)
   - Deploy to staging environment (mainnet)
   - Limited team testing with real funds
   - Monitor for errors in Sentry

### 8.3 Production Release

1. **Deployment**
   - Merge to master
   - Deploy to production
   - Monitor Sentry for new errors

2. **Post-Launch Monitoring**
   - Watch for payment failures
   - Monitor transaction success rate
   - Gather user feedback

---

## Appendix A: Token Amount Conversions

```dart
// Conversion helpers (match Turbo SDK)
BigInt arToWinston(double ar) => BigInt.from(ar * 1e12);
BigInt arioToMario(double ario) => BigInt.from(ario * 1e6);
BigInt ethToWei(double eth) => BigInt.from(eth * 1e18);
BigInt solToLamports(double sol) => BigInt.from(sol * 1e9);
BigInt usdcToSmallest(double usdc) => BigInt.from(usdc * 1e6);

// Reverse conversions for display
double winstonToAr(BigInt winston) => winston.toDouble() / 1e12;
double marioToArio(BigInt mario) => mario.toDouble() / 1e6;
double weiToEth(BigInt wei) => wei.toDouble() / 1e18;
double lamportsToSol(BigInt lamports) => lamports.toDouble() / 1e9;
double smallestToUsdc(BigInt smallest) => smallest.toDouble() / 1e6;
```

## Appendix B: Block Explorer URL Patterns

```dart
String getExplorerTxUrl(CryptoToken token, String txId, bool isTestnet) {
  return switch (token) {
    CryptoToken.arioAO => 'https://scan.ar.io/#/message/$txId',
    CryptoToken.arioBase || CryptoToken.ethBase || CryptoToken.usdcBase =>
      isTestnet
        ? 'https://sepolia.basescan.org/tx/$txId'
        : 'https://basescan.org/tx/$txId',
    CryptoToken.ethL1 || CryptoToken.usdcEth =>
      isTestnet
        ? 'https://sepolia.etherscan.io/tx/$txId'
        : 'https://etherscan.io/tx/$txId',
    CryptoToken.sol =>
      isTestnet
        ? 'https://solscan.io/tx/$txId?cluster=devnet'
        : 'https://solscan.io/tx/$txId',
  };
}
```

## Appendix C: Address Validation Regex

```dart
bool isValidEthereumAddress(String address) =>
  RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address);

bool isValidSolanaAddress(String address) =>
  RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(address);

bool isValidArweaveAddress(String address) =>
  RegExp(r'^[a-zA-Z0-9_-]{43}$').hasMatch(address);
```

## Appendix D: EIP-3085 Network Parameters (for wallet_addEthereumChain)

```dart
Map<String, dynamic> getBaseNetworkParams(bool isTestnet) => {
  'chainId': isTestnet ? '0x14a34' : '0x2105', // 84532 : 8453
  'chainName': isTestnet ? 'Base Sepolia' : 'Base',
  'nativeCurrency': {
    'name': 'Ethereum',
    'symbol': 'ETH',
    'decimals': 18,
  },
  'rpcUrls': [isTestnet ? 'https://sepolia.base.org' : 'https://mainnet.base.org'],
  'blockExplorerUrls': [isTestnet ? 'https://sepolia.basescan.org' : 'https://basescan.org'],
};
```
