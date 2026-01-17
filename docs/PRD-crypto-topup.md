# PRD: Cryptocurrency Top-Up for ArDrive

## Overview

Extend ArDrive's existing Stripe-based top-up flow to support cryptocurrency payments. Users will be able to purchase Turbo credits using various cryptocurrencies across multiple chains, with credits automatically applied to their logged-in Arweave wallet.

## Goals

1. Provide crypto-native users a seamless way to purchase Turbo credits without credit cards
2. Support the fastest and most cost-effective payment options first
3. Maintain a clean, intuitive UX that integrates naturally with the existing top-up flow
4. Enable transaction recovery for failed payments

## Non-Goals

- Cross-wallet top-ups (topping up a different wallet than logged-in)
- Mobile platform support (web only for initial release)
- Manual payment flow (send-and-paste transaction ID)
- Fiat on-ramp integration (Moonpay, etc.)

---

## Specifications

| Parameter | Value |
|-----------|-------|
| Minimum top-up | $0.01 USD equivalent |
| Maximum top-up | $5,000 USD equivalent |
| Session timeout | 25 minutes (shared with Stripe flow) |
| Promo codes | Supported for crypto payments |
| Platform | Web only (initial release) |

---

## Supported Payment Methods

### Token Priority (Ordered by Speed)

| Priority | Token | Chain | Wallet Type | Confirmation Time | Notes |
|----------|-------|-------|-------------|-------------------|-------|
| 1 | ARIO | AO | Arweave (logged-in) | Instant - 3 min | No extra wallet needed |
| 2 | ARIO | Base L2 | Ethereum | Instant - 3 min | Low gas fees |
| 3 | SOL | Solana | Solana (Phantom) | 1-2 min | Low fees |
| 4 | USDC | Base L2 | Ethereum | Instant - 3 min | Stablecoin, low gas |
| 5 | ETH | Base L2 | Ethereum | Instant - 3 min | Low gas fees |
| 6 | USDC | Ethereum L1 | Ethereum | 10-30 min | Stablecoin, higher gas |
| 7 | ETH | Ethereum L1 | Ethereum | 10-30 min | Higher gas fees |

### Wallet Requirements

| Wallet Type | Supported Wallets | Connection Method |
|-------------|-------------------|-------------------|
| Arweave | ArConnect, Wander | Already logged in (`window.arweaveWallet`) |
| Ethereum | MetaMask, Rainbow, WalletConnect, Coinbase | RainbowKit |
| Solana | Phantom, Solflare | Solana Wallet Adapter |

---

## User Experience

### Design System Alignment

All UI follows the existing ArDrive design patterns:
- **Modal**: `ArDriveModal` with max-width 575px, 40px padding, `themeBgCanvas` background
- **Typography**: `ArDriveTypography` - `leadBold` for titles, `buttonNormalBold` for body, `smallBold` for labels
- **Buttons**: `ArDriveButton` - primary (143x44px), secondary with border, text-only for back navigation
- **Cards**: `ArDriveCard` with 8px border radius, `themeBgSurface` background
- **Inputs**: `ArDriveTextField` with validation states (default/success/error borders)
- **Colors**: Semantic colors from theme (`themeFgDefault`, `themeFgMuted`, `themeSuccessDefault`, `themeErrorDefault`)

---

## Flow Architecture

### Entry Point

The existing "Add Turbo Credits" button opens the top-up modal. A tab bar is added at the top:

```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   ┌──────────────────┐  ┌──────────────────┐               │
│   │   Credit Card    │  │  Cryptocurrency  │               │
│   └──────────────────┘  └──────────────────┘               │
│   ─────────────────────  ═══════════════════               │
│                                                             │
│   (Tab content area)                                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Tab Implementation:**
- Use `ArDriveButton` with `ArDriveButtonStyle.secondary` for inactive tab
- Use bottom border highlight for active tab (2px, `themeFgDefault`)
- Tab switching preserves state within each flow

---

## Crypto Top-Up Flow States

### State Machine

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  TokenSelection ──────► WalletConnection ──────┐           │
│       │                  (if needed)           │           │
│       │                                        │           │
│       ▼                                        ▼           │
│  AmountEntry ◄─────────────────────────────────┘           │
│       │                                                     │
│       ▼                                                     │
│  Confirmation                                               │
│       │                                                     │
│       ├──► Processing ──► Success                          │
│       │         │                                           │
│       │         ▼                                           │
│       └──► Error ◄───────┘                                 │
│              │                                              │
│              └──► TransactionRetry                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Screen Specifications

### 1. Token Selection Screen

**Purpose:** User selects which cryptocurrency to pay with.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   [ Credit Card ]  [• Cryptocurrency ]                     │
│   ────────────────  ══════════════════                     │
│                                                             │
│   Current Balance                                           │
│   2.50 Credits                              (themeFgMuted)  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Select Payment Token                      (smallBold)     │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [ARIO icon]  ARIO on AO                            │  │
│   │               Instant · Uses your ArDrive wallet    │  │
│   │                                        [Recommended]│  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [ARIO icon]  ARIO on AO (via Ethereum wallet)      │  │
│   │               Instant · Requires one-time signature │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   Requires Ethereum Wallet              (captionBold, muted)│
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [ARIO icon]  ARIO on Base                          │  │
│   │               ~3 min · Low fees                     │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [USDC icon]  USDC on Base                          │  │
│   │               ~3 min · Stablecoin                   │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [ETH icon]   ETH on Base                           │  │
│   │               ~3 min · Low fees                     │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [USDC icon]  USDC on Ethereum                      │  │
│   │               ~15 min · Higher fees                 │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [ETH icon]   ETH on Ethereum                       │  │
│   │               ~15 min · Higher fees                 │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   Requires Solana Wallet                (captionBold, muted)│
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [SOL icon]   SOL                                   │  │
│   │               ~2 min · Low fees                     │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Component Specifications:**

| Element | Component | Style |
|---------|-----------|-------|
| Balance label | `Text` | `smallBold()`, `themeFgDefault` |
| Balance value | `Text` | `buttonXLargeBold()`, `themeFgMuted` |
| Section header | `Text` | `smallBold()`, `themeFgDefault` |
| Wallet requirement label | `Text` | `captionBold()`, `themeFgSubtle` |
| Token card | `ArDriveCard` | `themeBgSurface`, 8px radius, hover state |
| Token name | `Text` | `buttonNormalBold()`, `themeFgDefault` |
| Token description | `Text` | `captionRegular()`, `themeFgMuted` |
| Recommended badge | `Container` | `themeAccentDefault` background, `captionBold()` |

**Behavior:**
- Token cards have hover state (border highlight)
- Clicking **ARIO on AO** proceeds directly to Amount Entry (wallet already connected via ArDrive login)
- Clicking **ARIO on AO (via Ethereum wallet)**:
  - If Ethereum wallet not connected: show Ethereum Wallet Connection screen
  - If connected but no AO signature cached: show AO Connect Signature screen
  - If connected and signature cached: proceed to Amount Entry
- Clicking Ethereum tokens (ARIO/ETH/USDC on Base, ETH/USDC on Ethereum) checks for connected Ethereum wallet
  - If connected: proceed to Amount Entry
  - If not connected: show Wallet Connection screen
- Clicking SOL checks for connected Solana wallet
  - If connected: proceed to Amount Entry
  - If not connected: show Wallet Connection screen

**Edge Cases:**
- If user has pending transaction from previous session, show banner: "You have a pending transaction. [View Status]"
- If user has active top-up in another tab, show warning: "You have an active top-up session in another tab. [Continue Here] [Cancel]"

---

### 2. Wallet Connection Screen (Ethereum)

**Purpose:** Connect an Ethereum wallet to pay with ETH/USDC/ARIO on Base.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Connect Ethereum Wallet                   (leadBold)      │
│                                                             │
│   To pay with USDC on Base, connect an             (body)   │
│   Ethereum-compatible wallet.                               │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [MetaMask fox]   MetaMask                          │  │
│   │                   Browser extension                 │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [Rainbow icon]   Rainbow                           │  │
│   │                   Mobile & browser                  │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [WC icon]        WalletConnect                     │  │
│   │                   Connect mobile wallet             │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [CB icon]        Coinbase Wallet                   │  │
│   │                   Browser & mobile                  │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Back                                      (text button)   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**States:**

1. **Default**: Show wallet options
2. **Connecting**: Show selected wallet with spinner, "Connecting to MetaMask..."
3. **Error**: Show error message with retry option

**Connecting State:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Connect Ethereum Wallet                   (leadBold)      │
│                                                             │
│                         [Spinner]                           │
│                                                             │
│   Connecting to MetaMask...                 (buttonNormal)  │
│                                                             │
│   Please approve the connection in your                     │
│   wallet extension.                         (caption,muted) │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Cancel                                    (text button)   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Connection Error State:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Connect Ethereum Wallet                   (leadBold)      │
│                                                             │
│   [Warning triangle icon]            (themeErrorDefault)    │
│                                                             │
│   Connection Failed                         (buttonNormal)  │
│                                                             │
│   User rejected the connection request.     (caption,muted) │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Back                    [Try Again]                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Behavior:**
- Clicking a wallet triggers RainbowKit connection flow
- On success: proceed to Amount Entry with wallet connected
- On rejection: show error state with "Try Again" option
- "Back" returns to Token Selection

---

### 3. Wallet Connection Screen (Solana)

**Purpose:** Connect a Solana wallet to pay with SOL.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Connect Solana Wallet                     (leadBold)      │
│                                                             │
│   To pay with SOL, connect a Solana wallet.        (body)   │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [Phantom ghost]  Phantom                           │  │
│   │                   Most popular Solana wallet        │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [Solflare icon]  Solflare                          │  │
│   │                   Browser & mobile                  │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Back                                      (text button)   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Behavior:** Same patterns as Ethereum wallet connection.

---

### 4. AO Connect Signature Screen

**Purpose:** One-time signature to enable Ethereum wallet to interact with AO network for ARIO payments.

**When Shown:** User selected "ARIO on AO (via Ethereum wallet)" and has connected their Ethereum wallet, but has not yet signed the AO connection message this session.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Connect to AO Network                       (leadBold)    │
│                                                             │
│   To pay with ARIO on AO using your Ethereum                │
│   wallet, we need to establish a secure connection.         │
│                                                             │
│   This requires a one-time signature (no transaction        │
│   or gas fee). This signature:                              │
│                                                             │
│   • Proves you own this wallet                              │
│   • Enables interaction with the AO network                 │
│   • Is cached for your session (won't ask again)            │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  Connected Wallet                       (caption)   │  │
│   │  0x1234...5678 (MetaMask)               (small)     │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Back                              [Sign & Connect]        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Signing State:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Connect to AO Network                       (leadBold)    │
│                                                             │
│                         [Spinner]                           │
│                                                             │
│   Waiting for signature...                (buttonNormal)    │
│                                                             │
│   Please sign the message in your wallet.  (caption,muted)  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Cancel                                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Error State:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Connect to AO Network                       (leadBold)    │
│                                                             │
│   [Warning triangle icon]              (themeErrorDefault)  │
│                                                             │
│   Signature Rejected                      (buttonNormal)    │
│                                                             │
│   You rejected the signature request.      (caption,muted)  │
│   This signature is required to proceed.                    │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Back                              [Try Again]             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Behavior:**
- "Sign & Connect" triggers wallet signature request for message: "Sign this message to connect your Ethereum wallet to ArDrive for ARIO payments on AO. This signature does not authorize any transaction."
- On success: cache the derived public key for the session, proceed to Amount Entry
- On rejection: show error state with "Try Again" option
- "Back" returns to Token Selection
- Signature is cached in memory (not localStorage) for security; cleared on page refresh or wallet disconnect

**Technical Note:** This signature enables `InjectedEthereumSigner` to derive the user's public key via ecrecover, which is required for signing AO data items from an Ethereum wallet.

---

### 5. Amount Entry Screen

**Purpose:** User enters the amount to top up with live price conversion.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   ← USDC on Base                            (leadBold)      │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  Connected Wallet                       (caption)   │  │
│   │  0x1234...5678                          (small)     │  │
│   │  Balance: 150.00 USDC                   (caption)   │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Amount (USD) *                            (label)         │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  $  [ 25.00                                    ]  ▼ │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   [ $10 ]  [ $25 ]  [ $50 ]  [ $100 ]       (preset btns)  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Promo Code                                (label)         │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  [ SUMMER2024                     ]     [Apply]     │  │
│   └─────────────────────────────────────────────────────┘  │
│   ✓ 10% discount applied                    (success text) │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  You Pay           25.00 USDC (~$25.00)             │  │
│   │  ───────────────────────────────────────────────    │  │
│   │  You Receive       2.45 Credits                     │  │
│   │  Storage           ~12.5 GB                         │  │
│   │  ───────────────────────────────────────────────    │  │
│   │  Network Fee       ~$0.01 (estimated)               │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   Credits will be added to your ArDrive wallet:            │
│   abc123...xyz789                           (caption,muted) │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Back                              [Continue]              │
│                                                             │
│   Quote expires in 4:32             (timer, caption)        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Component Specifications:**

| Element | Component | Style |
|---------|-----------|-------|
| Back arrow + title | `GestureDetector` + `Text` | `leadBold()`, clickable |
| Wallet card | `ArDriveCard` | `themeBgSurface`, compact padding |
| Amount input | `ArDriveTextField` | with `$` prefix, number keyboard |
| Preset buttons | `ArDriveButton` | 75x44px, secondary style, selected state |
| Promo code field | `ArDriveTextField` | with suffix "Apply" button |
| Summary card | `ArDriveCard` | `shadow` background color |
| Timer | `TimerWidget` | `captionBold()`, color changes at <60s |
| Continue button | `ArDriveButton` | primary, 143x44px |

**Input Modes:**
- Default: Enter USD amount (converted to token amount)
- Dropdown allows switching to token amount input

**Dropdown Options:**
```
▼ Amount (USD)
  Amount (USDC)
```

**Validation Rules:**
- Minimum: $0.01
- Maximum: $5,000
- Cannot exceed wallet balance
- Must be valid number

**Validation States:**

*Insufficient Balance:*
```
┌─────────────────────────────────────────────────────────────┐
│  $  [ 200.00                                          ]  ▼ │
└─────────────────────────────────────────────────────────────┘
⚠ Insufficient balance. You have 150.00 USDC.  (error text)
```

*Below Minimum:*
```
┌─────────────────────────────────────────────────────────────┐
│  $  [ 0.001                                           ]  ▼ │
└─────────────────────────────────────────────────────────────┘
⚠ Minimum amount is $0.01.                     (error text)
```

*Above Maximum:*
```
┌─────────────────────────────────────────────────────────────┐
│  $  [ 6000                                            ]  ▼ │
└─────────────────────────────────────────────────────────────┘
⚠ Maximum amount is $5,000.                    (error text)
```

**Promo Code States:**

*Validating:*
```
[ SUMMER2024                     ]     [Spinner]
```

*Valid:*
```
[ SUMMER2024                     ]     [✓]
✓ 10% discount applied                 (themeSuccessDefault)
```

*Invalid:*
```
[ INVALIDCODE                    ]     [Apply]
✗ Promo code is invalid or expired     (themeErrorDefault)
```

**Live Pricing Behavior:**
- Debounce 500ms after user stops typing
- Show skeleton/shimmer while fetching
- Update "You Pay", "You Receive", "Storage" values
- If quote expires (5 min), auto-refresh

**Timer Behavior:**
- Counts down from quote expiration time
- Yellow warning at < 60 seconds
- Red warning at < 30 seconds
- Auto-refreshes quote when expired

**Button States:**
- **Disabled** if: amount invalid, insufficient balance, or loading
- **Enabled** when: valid amount within balance and quote loaded

**Gas Fee Estimation:**

The "Network Fee" line shows estimated gas costs for blockchain transactions:

| Token | Gas Estimation Method |
|-------|----------------------|
| ARIO on AO | No gas fee (uses existing Arweave wallet) |
| ARIO on AO (via ETH) | No gas fee (signature only, no on-chain tx) |
| ETH (L1 or Base) | `eth_estimateGas` + `eth_gasPrice` |
| USDC (L1 or Base) | `eth_estimateGas` for ERC-20 transfer |
| ARIO on Base | `eth_estimateGas` for ERC-20 transfer |
| SOL | `getRecentPrioritizationFees` + base fee |

**Insufficient Funds for Gas:**
If user has enough tokens but not enough for gas:
```
┌─────────────────────────────────────────────────────────────┐
│  $  [ 149.95                                           ]  ▼ │
└─────────────────────────────────────────────────────────────┘
⚠ Insufficient funds. You need ~0.05 ETH for gas fees.
   Available: 150.00 USDC + 0.001 ETH              (error text)
```

**Note:** For native token payments (ETH, SOL), the gas must come from the same token, so validation must check `balance >= amount + estimatedGas`.

---

### 6. Confirmation Screen

**Purpose:** Final review before signing the transaction.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Confirm Payment                           (leadBold)      │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │                                                     │  │
│   │  [Turbo Logo]                                       │  │
│   │                                                     │  │
│   │                    2.45                              │  │
│   │                   Credits               (headline4)  │  │
│   │                                                     │  │
│   │  ─────────────────────────────────────────────────  │  │
│   │                                                     │  │
│   │  Token            USDC on Base                      │  │
│   │  ─────────────────────────────────────────────────  │  │
│   │  Amount           25.00 USDC                        │  │
│   │  ─────────────────────────────────────────────────  │  │
│   │  USD Value        ~$25.00                           │  │
│   │  ─────────────────────────────────────────────────  │  │
│   │  Storage          ~12.5 GB                          │  │
│   │  ─────────────────────────────────────────────────  │  │
│   │  Network Fee      ~$0.01                            │  │
│   │  ─────────────────────────────────────────────────  │  │
│   │                                                     │  │
│   │  Subtotal         $25.00                            │  │
│   │  Discount         -$2.50 (10%)                      │  │
│   │  ─────────────────────────────────────────────────  │  │
│   │  Total            $22.50                (bold)      │  │
│   │                                                     │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   From: 0x1234...5678 (MetaMask)            (caption)       │
│   To:   abc123...xyz789 (ArDrive)           (caption)       │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   ⚠ This will open your wallet to sign                     │
│     the transaction.                        (caption,muted) │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Back                              [Confirm & Pay]         │
│                                                             │
│   Quote expires in 3:45             (timer)                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Behavior:**
- "Confirm & Pay" triggers wallet signature request
- If wrong network detected, auto-switch before signing
- Show loading state on button while wallet is open

**Network Switching:**
If user's wallet is on wrong network:
```
┌─────────────────────────────────────────────────────────────┐
│   ⚠ Your wallet is on Ethereum Mainnet.                    │
│     We'll switch you to Base before payment.               │
└─────────────────────────────────────────────────────────────┘
```

**Button Loading State:**
```
   Back                              [ ◐ Waiting... ]
```

---

### 7. Processing Screen

**Purpose:** Show transaction status while waiting for blockchain confirmation.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│                                                             │
│                                                             │
│                         [Spinner]                           │
│                                                             │
│   Processing Payment                        (leadBold)      │
│                                                             │
│   Waiting for blockchain confirmation...    (buttonNormal)  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Transaction ID                            (caption,muted) │
│   0xabcdef1234567890...                     (small,mono)    │
│   [Copy] [View on Explorer ↗]               (text buttons)  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Estimated time: ~3 minutes                (caption)       │
│                                                             │
│   You can close this dialog. Your credits                   │
│   will appear once the transaction confirms. (caption,muted)│
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│                              [Close]                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Behavior:**
- User can close and continue using ArDrive
- Store transaction ID locally for recovery
- Poll for transaction confirmation in background
- On confirmation, show success notification (if modal closed) or navigate to Success screen

**If user closes:**
- Show toast: "Your payment is processing. Credits will appear shortly."
- Update balance in header when confirmed

---

### 8. Success Screen

**Purpose:** Confirm successful payment.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│                    [Confetti animation]                     │
│                                                             │
│                         [✓]                 (green, 40px)   │
│                                                             │
│   Payment Complete!                         (leadBold)      │
│                                                             │
│   2.45 Credits Added                        (buttonNormal)  │
│                                                             │
│   Your new balance: 4.95 Credits            (caption,muted) │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Transaction ID                            (caption,muted) │
│   0xabcdef1234567890...                     (small,mono)    │
│   [View on Explorer ↗]                      (text button)   │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│                              [Done]                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Component Specifications:**
- Use existing `ConfettiWidget` from success view
- Green checkmark icon: `ArDriveIcons.checkCirle(size: 40, color: themeSuccessDefault)`
- "Done" button closes modal and refreshes balance

---

### 9. Error Screen

**Purpose:** Handle payment failures with recovery options.

**Layout (General Error):**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│                                                             │
│                         [△]                 (red, 50px)     │
│                                                             │
│   Payment Failed                            (leadBold)      │
│                                                             │
│   The transaction could not be completed.   (buttonNormal)  │
│                                                             │
│   Error: User rejected the request          (caption,muted) │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Back                              [Try Again]             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Error Types and Messages:**

| Error Type | Title | Message | Actions |
|------------|-------|---------|---------|
| User rejected | Payment Cancelled | You cancelled the transaction in your wallet. | Back, Try Again |
| Insufficient funds | Insufficient Funds | You don't have enough {token} to complete this payment. | Back |
| Network error | Network Error | Could not connect to the blockchain. Please check your connection. | Back, Try Again |
| Quote expired | Quote Expired | The price quote has expired. Please try again for a new quote. | Get New Quote |
| Transaction failed | Transaction Failed | The transaction failed on the blockchain. | Back, Try Again |

**Transaction Pending/Recovery Error:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│                         [!]                 (yellow, 50px)  │
│                                                             │
│   Transaction Pending                       (leadBold)      │
│                                                             │
│   Your payment was submitted but we couldn't               │
│   confirm it was received.                  (buttonNormal)  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Transaction ID                            (caption,muted) │
│   0xabcdef1234567890...                     (small,mono)    │
│   [Copy] [View on Explorer ↗]                               │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   If this transaction confirmed on-chain,                   │
│   you can retry processing to receive                       │
│   your credits.                             (caption,muted) │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Cancel                            [Retry Processing]      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Retry Processing Behavior:**
1. User clicks "Retry Processing"
2. Call `PaymentService.submitCryptoTransaction(tokenType, txId)`
3. If successful: navigate to Success
4. If still pending: show "Still processing, please wait..."
5. If failed: show error with option to contact support

---

### 10. Session Timeout Screen

**Purpose:** Handle 25-minute session expiration.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│                         [Clock icon]        (muted, 50px)   │
│                                                             │
│   Session Expired                           (leadBold)      │
│                                                             │
│   Your session has timed out for security                   │
│   reasons. Please start again.              (buttonNormal)  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│                              [Start Over]                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### 11. Manual Network Switch Screen

**Purpose:** Guide user through manual network switching when automatic switch fails.

**When Shown:** User's wallet rejected the automatic network switch request, or the network couldn't be added automatically.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Switch to Base Network                      (leadBold)    │
│                                                             │
│   Your wallet is currently on Ethereum Mainnet.             │
│   Please switch to Base to continue.          (buttonNormal)│
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   How to switch manually:                     (smallBold)   │
│                                                             │
│   1. Open your wallet extension                             │
│   2. Click the network dropdown (top of wallet)             │
│   3. Select "Base" from the list                            │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Don't see Base in your wallet?              (smallBold)   │
│                                                             │
│   [Add Base Network]                          (secondary)   │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Back                              [I've Switched]         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Adding Network State (after clicking "Add Base Network"):**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Add Base Network                            (leadBold)    │
│                                                             │
│                         [Spinner]                           │
│                                                             │
│   Adding Base network to your wallet...      (buttonNormal) │
│                                                             │
│   Please approve the request in your wallet.  (caption,muted)│
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Cancel                                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Manual Add Instructions (if automatic add fails):**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   Add Base Network Manually                   (leadBold)    │
│                                                             │
│   Please add Base network to your wallet with               │
│   these settings:                             (buttonNormal)│
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Network Name     Base                       [Copy]        │
│   RPC URL          https://mainnet.base.org   [Copy]        │
│   Chain ID         8453                       [Copy]        │
│   Currency Symbol  ETH                        [Copy]        │
│   Block Explorer   https://basescan.org       [Copy]        │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Back                              [I've Added It]         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Behavior:**
- "I've Switched" / "I've Added It" re-checks the current network
- If correct network: proceed to Confirmation
- If still wrong: show inline error "Still on wrong network. Please verify your wallet is on Base."
- "Add Base Network" attempts `wallet_addEthereumChain` RPC call
- If add fails: show manual instructions with copyable fields

---

### 12. Price Volatility Warning Modal

**Purpose:** Alert user when price changes significantly during their session.

**When Shown:** Quote refresh detects >5% price change from original quote.

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   [Warning triangle]                   (themeWarningDefault)│
│                                                             │
│   Price Changed                               (leadBold)    │
│                                                             │
│   The price has changed since your original quote.          │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Original:        2.45 Credits for 25.00 USDC              │
│   New:             2.32 Credits for 25.00 USDC              │
│   Difference:      -5.3%                      (error color) │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   Cancel                              [Accept New Price]    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Behavior:**
- Shown as overlay on current screen
- "Accept New Price" dismisses warning and continues with new quote
- "Cancel" returns to Amount Entry to allow user to reconsider
- Only shown once per quote refresh (don't re-warn if user already accepted)

---

## Edge Cases & Error Handling

### Wallet Disconnection Mid-Flow

If wallet disconnects during Amount Entry or Confirmation:
1. Show inline error: "Wallet disconnected. Please reconnect to continue."
2. Provide "Reconnect Wallet" button
3. On reconnect, verify same address; if different, restart flow

### Account Switch Mid-Flow

If user switches accounts in their wallet (different from disconnect):
1. Detect via `accountsChanged` event listener
2. Show warning: "Wallet account changed. Your payment details have been reset."
3. Clear all payment state (quote, amount, promo code)
4. Clear cached AO signature (if applicable)
5. Return to Token Selection with new address
6. Do NOT auto-proceed - let user re-select token and re-enter amount

### Network Switch Failure

If auto network switch fails:
1. Show error: "Please switch to {network} in your wallet to continue."
2. Provide manual instructions
3. "Try Again" button to retry switch

### Price Volatility

If price changes significantly (>5%) during flow:
1. Show warning: "Price has changed since your quote. New total: $X"
2. Require user to acknowledge before proceeding

### Browser Extension Not Installed

If user selects MetaMask but extension not detected:
```
┌─────────────────────────────────────────────────────────────┐
│   MetaMask not detected                     (leadBold)      │
│                                                             │
│   Install the MetaMask browser extension                    │
│   to continue.                              (buttonNormal)  │
│                                                             │
│   [Install MetaMask ↗]                  [Use Different Wallet]
└─────────────────────────────────────────────────────────────┘
```

### Concurrent Top-Up Prevention

If user has an active top-up session in another tab:

**Detection:**
- Use `localStorage` with a session lock key: `ardrive_topup_session_lock`
- Lock contains: `{ tabId, timestamp, state }` (e.g., `{ tabId: "abc123", timestamp: 1234567890, state: "amount_entry" }`)
- On modal open, check for existing lock
- Listen to `storage` event for cross-tab changes

**Active Session Warning:**
```
┌─────────────────────────────────────────────────────────────┐
│                                                     [X]     │
│                                                             │
│   [Warning triangle]                   (themeWarningDefault)│
│                                                             │
│   Active Session Detected                     (leadBold)    │
│                                                             │
│   You have a top-up in progress in another tab.             │
│   Only one top-up session can be active at a time.          │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│   [Cancel Other Session]              [Go to Other Tab]     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Behavior:**
- "Cancel Other Session" clears the lock and proceeds with current tab
- "Go to Other Tab" closes modal (user navigates manually)
- Lock auto-expires after 30 minutes (stale session protection)
- Lock is released when modal closes or payment completes

### Modal Close During Processing

If user closes modal while payment is processing:
1. Show toast: "Payment processing in background. You'll be notified when complete."
2. Continue polling for transaction confirmation
3. On confirmation, show system notification (if tab is active) or update balance silently
4. If user reopens top-up modal, show Processing screen with transaction status

---

## Technical Architecture

### New Dependencies

```yaml
# pubspec.yaml additions
dependencies:
  # Ethereum wallet connection (JS interop)
  # Note: Use existing js package for window.ethereum access

  # Consider for Solana
  # solana_web3: for Solana RPC calls via JS interop
```

### JavaScript Interop Layer

Create JS interop for wallet interactions:

```dart
// lib/turbo/services/ethereum_wallet_interop.dart
@JS('window.ethereum')
external dynamic get ethereum;

@JS('window.solana')
external dynamic get solana;
```

### Directory Structure

```
lib/turbo/
├── topup/
│   ├── blocs/
│   │   ├── crypto_topup/
│   │   │   ├── crypto_topup_bloc.dart
│   │   │   ├── crypto_topup_event.dart
│   │   │   └── crypto_topup_state.dart
│   │   ├── ethereum_wallet/
│   │   │   ├── ethereum_wallet_cubit.dart
│   │   │   └── ethereum_wallet_state.dart
│   │   ├── solana_wallet/
│   │   │   ├── solana_wallet_cubit.dart
│   │   │   └── solana_wallet_state.dart
│   │   └── ... (existing blocs)
│   ├── models/
│   │   ├── crypto_token.dart
│   │   ├── crypto_quote.dart
│   │   ├── wallet_connection_state.dart
│   │   └── ... (existing models)
│   └── views/
│       ├── crypto/
│       │   ├── crypto_topup_tab.dart
│       │   ├── token_selection_view.dart
│       │   ├── ethereum_wallet_connection_view.dart
│       │   ├── solana_wallet_connection_view.dart
│       │   ├── crypto_amount_entry_view.dart
│       │   ├── crypto_confirmation_view.dart
│       │   ├── crypto_processing_view.dart
│       │   └── crypto_success_view.dart
│       ├── components/
│       │   ├── payment_method_tabs.dart
│       │   ├── token_card.dart
│       │   ├── wallet_card.dart
│       │   ├── crypto_summary_card.dart
│       │   └── transaction_status.dart
│       └── ... (existing views)
├── services/
│   ├── payment_service.dart          # Extend with crypto endpoints
│   ├── ethereum_wallet_service.dart  # New
│   ├── solana_wallet_service.dart    # New
│   └── crypto_transaction_storage.dart  # Local storage for recovery
└── turbo.dart                        # Add CryptoPaymentProvider
```

### Data Models

```dart
enum CryptoToken {
  arioAO,         // ARIO on AO (Arweave wallet)
  arioAOViaEth,   // ARIO on AO (via Ethereum wallet - requires InjectedEthereumSigner)
  arioBase,       // ARIO on Base L2
  sol,            // SOL on Solana
  usdcBase,       // USDC on Base L2
  ethBase,        // ETH on Base L2
  usdcEth,        // USDC on Ethereum L1
  ethL1,          // ETH on Ethereum L1
}

extension CryptoTokenX on CryptoToken {
  String get displayName => switch (this) {
    CryptoToken.arioAO => 'ARIO on AO',
    CryptoToken.arioAOViaEth => 'ARIO on AO (via Ethereum wallet)',
    CryptoToken.arioBase => 'ARIO on Base',
    CryptoToken.sol => 'SOL',
    CryptoToken.usdcBase => 'USDC on Base',
    CryptoToken.ethBase => 'ETH on Base',
    CryptoToken.usdcEth => 'USDC on Ethereum',
    CryptoToken.ethL1 => 'ETH on Ethereum',
  };

  String get symbol => switch (this) {
    CryptoToken.arioAO || CryptoToken.arioAOViaEth || CryptoToken.arioBase => 'ARIO',
    CryptoToken.sol => 'SOL',
    CryptoToken.usdcBase || CryptoToken.usdcEth => 'USDC',
    CryptoToken.ethBase || CryptoToken.ethL1 => 'ETH',
  };

  String get chain => switch (this) {
    CryptoToken.arioAO || CryptoToken.arioAOViaEth => 'AO',
    CryptoToken.arioBase || CryptoToken.usdcBase || CryptoToken.ethBase => 'Base',
    CryptoToken.sol => 'Solana',
    CryptoToken.usdcEth || CryptoToken.ethL1 => 'Ethereum',
  };

  int get decimals => switch (this) {
    CryptoToken.arioAO || CryptoToken.arioAOViaEth || CryptoToken.arioBase => 6,
    CryptoToken.sol => 9,
    CryptoToken.usdcBase || CryptoToken.usdcEth => 6,
    CryptoToken.ethBase || CryptoToken.ethL1 => 18,
  };

  int? get chainId => switch (this) {
    CryptoToken.arioBase || CryptoToken.usdcBase || CryptoToken.ethBase => 8453,
    CryptoToken.usdcEth || CryptoToken.ethL1 => 1,
    _ => null,  // arioAO, arioAOViaEth, sol don't have EVM chain IDs
  };

  WalletType get walletType => switch (this) {
    CryptoToken.arioAO => WalletType.arweave,
    CryptoToken.arioAOViaEth || CryptoToken.arioBase || CryptoToken.usdcBase ||
    CryptoToken.ethBase || CryptoToken.usdcEth ||
    CryptoToken.ethL1 => WalletType.ethereum,
    CryptoToken.sol => WalletType.solana,
  };

  Duration get estimatedConfirmationTime => switch (this) {
    CryptoToken.arioAO || CryptoToken.arioAOViaEth || CryptoToken.arioBase ||
    CryptoToken.usdcBase || CryptoToken.ethBase => Duration(minutes: 3),
    CryptoToken.sol => Duration(minutes: 2),
    CryptoToken.usdcEth || CryptoToken.ethL1 => Duration(minutes: 15),
  };

  bool get isFast => estimatedConfirmationTime.inMinutes <= 5;

  /// Whether this token requires the AO connect signature flow
  bool get requiresAOConnectSignature => this == CryptoToken.arioAOViaEth;
}

enum WalletType { arweave, ethereum, solana }

class CryptoQuote {
  final CryptoToken token;
  final BigInt tokenAmount;
  final BigInt wincAmount;
  final double creditsDisplay;
  final double estimatedStorageGiB;
  final double usdValue;
  final double? networkFeeUsd;
  final Adjustment? adjustment;  // Promo code discount
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  Duration get timeRemaining => expiresAt.difference(DateTime.now());
}

class CryptoPaymentResult {
  final bool success;
  final String? transactionId;
  final String? errorMessage;
  final CryptoPaymentStatus status;
}

enum CryptoPaymentStatus {
  success,
  pending,
  failed,
  userRejected,
  insufficientFunds,
  networkError,
  wrongNetwork,
  quoteExpired,
}

class PendingCryptoTransaction {
  final String transactionId;
  final CryptoToken token;
  final BigInt tokenAmount;
  final String arweaveAddress;
  final DateTime createdAt;
}
```

### BLoC Architecture

```dart
// Events
sealed class CryptoTopupEvent {}

class CryptoTopupStarted extends CryptoTopupEvent {}

class CryptoTopupTokenSelected extends CryptoTopupEvent {
  final CryptoToken token;
}

class CryptoTopupWalletConnected extends CryptoTopupEvent {
  final String address;
  final WalletType walletType;
}

class CryptoTopupWalletConnectionFailed extends CryptoTopupEvent {
  final String error;
}

class CryptoTopupAmountChanged extends CryptoTopupEvent {
  final double amount;
  final bool isUsdAmount;
}

class CryptoTopupPromoCodeSubmitted extends CryptoTopupEvent {
  final String promoCode;
}

class CryptoTopupProceedToConfirmation extends CryptoTopupEvent {}

class CryptoTopupPaymentConfirmed extends CryptoTopupEvent {}

class CryptoTopupRetryTransaction extends CryptoTopupEvent {
  final String transactionId;
}

class CryptoTopupBackPressed extends CryptoTopupEvent {}

class CryptoTopupSessionExpired extends CryptoTopupEvent {}

// States
sealed class CryptoTopupState {}

class CryptoTopupInitial extends CryptoTopupState {}

class CryptoTopupTokenSelection extends CryptoTopupState {
  final double currentBalance;
  final String? ethereumAddress;
  final String? solanaAddress;
  final PendingCryptoTransaction? pendingTransaction;
}

class CryptoTopupWalletConnection extends CryptoTopupState {
  final CryptoToken selectedToken;
  final WalletType requiredWalletType;
  final bool isConnecting;
  final String? error;
}

class CryptoTopupAmountEntry extends CryptoTopupState {
  final CryptoToken token;
  final String walletAddress;
  final BigInt walletBalance;
  final double? usdAmount;
  final CryptoQuote? quote;
  final bool isLoadingQuote;
  final String? promoCode;
  final bool isValidatingPromo;
  final String? promoError;
  final String? amountError;
}

class CryptoTopupConfirmation extends CryptoTopupState {
  final CryptoToken token;
  final CryptoQuote quote;
  final String fromAddress;
  final String toAddress;
  final bool isProcessing;
  final bool needsNetworkSwitch;
  final int? currentChainId;
}

class CryptoTopupProcessing extends CryptoTopupState {
  final String transactionId;
  final CryptoToken token;
  final Duration estimatedTime;
}

class CryptoTopupSuccess extends CryptoTopupState {
  final String transactionId;
  final double creditsAdded;
  final double newBalance;
  final CryptoToken token;
}

class CryptoTopupError extends CryptoTopupState {
  final CryptoPaymentStatus errorType;
  final String message;
  final String? transactionId;
  final bool canRetry;
}

class CryptoTopupSessionTimeout extends CryptoTopupState {}
```

### API Endpoints

```dart
// PaymentService extensions
extension CryptoPaymentServiceX on PaymentService {
  /// GET /info
  /// Returns Turbo wallet addresses for each token
  Future<Map<String, String>> getTurboWalletAddresses();

  /// GET /v1/price/{tokenType}/{amount}
  /// Get credits for crypto amount
  Future<CryptoQuote> getCryptoQuote({
    required String tokenType,
    required BigInt tokenAmount,
    String? promoCode,
  });

  /// POST /v1/top-up/crypto/{tokenType}
  /// Submit transaction for processing
  Future<CryptoPaymentResult> submitCryptoTransaction({
    required String tokenType,
    required String transactionId,
  });
}
```

### Network Configuration

```dart
class CryptoNetworkConfig {
  static const Map<CryptoToken, NetworkConfig> production = {
    CryptoToken.arioAO: NetworkConfig(
      rpcUrl: 'https://arweave.net',
    ),
    CryptoToken.arioBase: NetworkConfig(
      chainId: 8453,
      chainName: 'Base',
      rpcUrl: 'https://mainnet.base.org',
      contractAddress: '0x138746adfA52909E5920def027f5a8dc1C7EfFb6',
      explorerUrl: 'https://basescan.org',
    ),
    CryptoToken.sol: NetworkConfig(
      rpcUrl: 'https://api.mainnet-beta.solana.com',
      explorerUrl: 'https://solscan.io',
    ),
    CryptoToken.usdcBase: NetworkConfig(
      chainId: 8453,
      chainName: 'Base',
      rpcUrl: 'https://mainnet.base.org',
      contractAddress: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
      explorerUrl: 'https://basescan.org',
    ),
    CryptoToken.ethBase: NetworkConfig(
      chainId: 8453,
      chainName: 'Base',
      rpcUrl: 'https://mainnet.base.org',
      explorerUrl: 'https://basescan.org',
    ),
    CryptoToken.usdcEth: NetworkConfig(
      chainId: 1,
      chainName: 'Ethereum',
      rpcUrl: 'https://ethereum.publicnode.com',
      contractAddress: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      explorerUrl: 'https://etherscan.io',
    ),
    CryptoToken.ethL1: NetworkConfig(
      chainId: 1,
      chainName: 'Ethereum',
      rpcUrl: 'https://ethereum.publicnode.com',
      explorerUrl: 'https://etherscan.io',
    ),
  };
}
```

### Local Storage for Transaction Recovery

```dart
class CryptoTransactionStorage {
  static const _key = 'pending_crypto_transactions';

  Future<void> savePendingTransaction(PendingCryptoTransaction tx);
  Future<PendingCryptoTransaction?> getPendingTransaction(String arweaveAddress);
  Future<void> removePendingTransaction(String transactionId);
  Future<List<PendingCryptoTransaction>> getAllPending();
}
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)

1. **Data Models & Configuration**
   - Create `CryptoToken` enum and extensions
   - Create quote, result, and state models
   - Set up network configuration

2. **Payment Service Extensions**
   - Add `/info` endpoint for wallet addresses
   - Add `/v1/price/{token}/{amount}` endpoint
   - Add `/v1/top-up/crypto/{token}` endpoint

3. **Local Storage**
   - Implement `CryptoTransactionStorage` for recovery

### Phase 2: Wallet Services (Week 2-3)

1. **Ethereum Wallet Service**
   - JS interop for `window.ethereum`
   - RainbowKit-style connection flow
   - Network switching
   - Balance fetching (native + ERC-20)
   - Transaction signing

2. **Solana Wallet Service**
   - JS interop for `window.solana`
   - Phantom connection flow
   - Balance fetching
   - Transaction signing

3. **ARIO on AO Integration**
   - Use existing `window.arweaveWallet`
   - Implement ARIO token transfer on AO

### Phase 3: BLoC & State Management (Week 3-4)

1. **CryptoTopupBloc**
   - Implement all events and states
   - Token selection logic
   - Wallet connection coordination
   - Quote fetching with debounce
   - Payment execution
   - Error handling

2. **Wallet Cubits**
   - `EthereumWalletCubit` for connection state
   - `SolanaWalletCubit` for connection state

3. **Session Management**
   - Integrate with existing `TurboSessionManager`
   - Handle 25-minute timeout

### Phase 4: UI Implementation (Week 4-5)

1. **Payment Method Tabs**
   - Add `PaymentMethodTabs` component
   - Integrate into existing `TurboTopupModal`
   - Maintain Stripe flow unchanged

2. **Token Selection View**
   - Token cards with icons
   - Wallet requirement grouping
   - Pending transaction banner

3. **Wallet Connection Views**
   - Ethereum wallet options
   - Solana wallet options
   - Connection states (loading, error)

4. **Amount Entry View**
   - Connected wallet display
   - Amount input with presets
   - Promo code field
   - Live pricing summary
   - Quote timer

5. **Confirmation View**
   - Payment summary card
   - Network switch warning
   - Confirm button states

6. **Processing & Success Views**
   - Transaction status
   - Copy/explorer links
   - Confetti animation

7. **Error Views**
   - Error type-specific messaging
   - Retry options
   - Transaction recovery

### Phase 5: Testing & Polish (Week 5-6)

1. **Unit Tests**
   - `CryptoTopupBloc` state transitions
   - Wallet service mocking
   - Price calculations

2. **Integration Tests**
   - Testnet transactions (Base Sepolia, Solana Devnet)
   - Full flow testing
   - Recovery flow testing

3. **Manual Testing**
   - All token paths
   - All wallet providers
   - Error scenarios
   - Session timeout

4. **Polish**
   - Animations and transitions
   - Loading states
   - Accessibility

---

## Localization Keys

Add to localization files:

```yaml
# Crypto top-up
cryptoTopup_selectToken: "Select Payment Token"
cryptoTopup_requiresEthereumWallet: "Requires Ethereum Wallet"
cryptoTopup_requiresSolanaWallet: "Requires Solana Wallet"
cryptoTopup_usesArDriveWallet: "Uses your ArDrive wallet"
cryptoTopup_recommended: "Recommended"
cryptoTopup_instant: "Instant"
cryptoTopup_lowFees: "Low fees"
cryptoTopup_stablecoin: "Stablecoin"
cryptoTopup_higherFees: "Higher fees"

# Wallet connection
walletConnection_connectEthereum: "Connect Ethereum Wallet"
walletConnection_connectSolana: "Connect Solana Wallet"
walletConnection_toPayWith: "To pay with {token}, connect {walletType}."
walletConnection_connecting: "Connecting to {wallet}..."
walletConnection_approveInWallet: "Please approve the connection in your wallet extension."
walletConnection_connectionFailed: "Connection Failed"
walletConnection_userRejected: "You rejected the connection request."

# Amount entry
cryptoAmount_connectedWallet: "Connected Wallet"
cryptoAmount_balance: "Balance: {amount} {token}"
cryptoAmount_amountUsd: "Amount (USD)"
cryptoAmount_amountToken: "Amount ({token})"
cryptoAmount_youPay: "You Pay"
cryptoAmount_youReceive: "You Receive"
cryptoAmount_storage: "Storage"
cryptoAmount_networkFee: "Network Fee"
cryptoAmount_estimated: "estimated"
cryptoAmount_creditsAddedTo: "Credits will be added to your ArDrive wallet:"
cryptoAmount_quoteExpires: "Quote expires in {time}"
cryptoAmount_insufficientBalance: "Insufficient balance. You have {amount} {token}."
cryptoAmount_minimumAmount: "Minimum amount is $0.01."
cryptoAmount_maximumAmount: "Maximum amount is $5,000."

# Confirmation
cryptoConfirm_title: "Confirm Payment"
cryptoConfirm_token: "Token"
cryptoConfirm_amount: "Amount"
cryptoConfirm_usdValue: "USD Value"
cryptoConfirm_from: "From"
cryptoConfirm_to: "To"
cryptoConfirm_walletWarning: "This will open your wallet to sign the transaction."
cryptoConfirm_confirmAndPay: "Confirm & Pay"
cryptoConfirm_waiting: "Waiting..."
cryptoConfirm_wrongNetwork: "Your wallet is on {current}. We'll switch you to {required} before payment."

# Processing
cryptoProcessing_title: "Processing Payment"
cryptoProcessing_waitingConfirmation: "Waiting for blockchain confirmation..."
cryptoProcessing_transactionId: "Transaction ID"
cryptoProcessing_estimatedTime: "Estimated time: ~{minutes} minutes"
cryptoProcessing_canClose: "You can close this dialog. Your credits will appear once the transaction confirms."
cryptoProcessing_copyTxId: "Copy"
cryptoProcessing_viewExplorer: "View on Explorer"

# Success
cryptoSuccess_title: "Payment Complete!"
cryptoSuccess_creditsAdded: "{amount} Credits Added"
cryptoSuccess_newBalance: "Your new balance: {amount} Credits"

# Errors
cryptoError_paymentFailed: "Payment Failed"
cryptoError_paymentCancelled: "Payment Cancelled"
cryptoError_insufficientFunds: "Insufficient Funds"
cryptoError_networkError: "Network Error"
cryptoError_quoteExpired: "Quote Expired"
cryptoError_transactionFailed: "Transaction Failed"
cryptoError_transactionPending: "Transaction Pending"
cryptoError_userRejected: "You cancelled the transaction in your wallet."
cryptoError_notEnoughToken: "You don't have enough {token} to complete this payment."
cryptoError_checkConnection: "Could not connect to the blockchain. Please check your connection."
cryptoError_priceExpired: "The price quote has expired. Please try again for a new quote."
cryptoError_txFailedOnChain: "The transaction failed on the blockchain."
cryptoError_pendingMessage: "Your payment was submitted but we couldn't confirm it was received."
cryptoError_retryMessage: "If this transaction confirmed on-chain, you can retry processing to receive your credits."
cryptoError_retryProcessing: "Retry Processing"
cryptoError_getNewQuote: "Get New Quote"

# Session
cryptoSession_expired: "Session Expired"
cryptoSession_expiredMessage: "Your session has timed out for security reasons. Please start again."
cryptoSession_startOver: "Start Over"

# AO Connect Signature
aoConnect_title: "Connect to AO Network"
aoConnect_description: "To pay with ARIO on AO using your Ethereum wallet, we need to establish a secure connection."
aoConnect_signatureInfo: "This requires a one-time signature (no transaction or gas fee). This signature:"
aoConnect_provesOwnership: "Proves you own this wallet"
aoConnect_enablesAO: "Enables interaction with the AO network"
aoConnect_cachedSession: "Is cached for your session (won't ask again)"
aoConnect_connectedWallet: "Connected Wallet"
aoConnect_signAndConnect: "Sign & Connect"
aoConnect_waitingSignature: "Waiting for signature..."
aoConnect_signInWallet: "Please sign the message in your wallet."
aoConnect_signatureRejected: "Signature Rejected"
aoConnect_signatureRequired: "You rejected the signature request. This signature is required to proceed."

# Manual Network Switch
networkSwitch_title: "Switch to {network} Network"
networkSwitch_wrongNetwork: "Your wallet is currently on {current}. Please switch to {required} to continue."
networkSwitch_howToSwitch: "How to switch manually:"
networkSwitch_step1: "Open your wallet extension"
networkSwitch_step2: "Click the network dropdown (top of wallet)"
networkSwitch_step3: "Select \"{network}\" from the list"
networkSwitch_dontSeeNetwork: "Don't see {network} in your wallet?"
networkSwitch_addNetwork: "Add {network} Network"
networkSwitch_addingNetwork: "Adding {network} network to your wallet..."
networkSwitch_approveAdd: "Please approve the request in your wallet."
networkSwitch_addManually: "Add {network} Network Manually"
networkSwitch_addManuallyDesc: "Please add {network} network to your wallet with these settings:"
networkSwitch_networkName: "Network Name"
networkSwitch_rpcUrl: "RPC URL"
networkSwitch_chainId: "Chain ID"
networkSwitch_currencySymbol: "Currency Symbol"
networkSwitch_blockExplorer: "Block Explorer"
networkSwitch_iveSwitched: "I've Switched"
networkSwitch_iveAddedIt: "I've Added It"
networkSwitch_stillWrongNetwork: "Still on wrong network. Please verify your wallet is on {network}."

# Price Volatility Warning
priceVolatility_title: "Price Changed"
priceVolatility_description: "The price has changed since your original quote."
priceVolatility_original: "Original"
priceVolatility_new: "New"
priceVolatility_difference: "Difference"
priceVolatility_acceptNewPrice: "Accept New Price"

# Concurrent Session Warning
concurrentSession_title: "Active Session Detected"
concurrentSession_description: "You have a top-up in progress in another tab. Only one top-up session can be active at a time."
concurrentSession_cancelOther: "Cancel Other Session"
concurrentSession_goToOther: "Go to Other Tab"

# Account Changed Warning
accountChanged_title: "Account Changed"
accountChanged_description: "Your wallet account changed. Your payment details have been reset."
accountChanged_continue: "Continue"

# Gas / Insufficient Funds
cryptoAmount_insufficientGas: "Insufficient funds. You need ~{amount} {token} for gas fees."
cryptoAmount_availableBalance: "Available: {tokenBalance} {token} + {gasBalance} {gasToken}"
```

---

## Success Metrics

1. **Adoption Rate**: % of top-ups using crypto vs credit card
2. **Completion Rate**: % of started crypto flows that complete successfully
3. **Token Distribution**: Usage breakdown by token type
4. **Error Rate**: % of failed transactions by error type
5. **Retry Success Rate**: % of retried transactions that succeed
6. **Average Transaction Time**: From confirm to credits received
7. **Wallet Provider Distribution**: Usage by wallet (MetaMask, Phantom, etc.)

---

## Security Considerations

1. **No Private Keys**: All signing in user's wallet; never handle keys
2. **Transaction Verification**: Verify parameters match quote before signing
3. **Network Validation**: Always verify correct network before transactions
4. **Quote Expiration**: Enforce quote expiration to prevent stale pricing
5. **Address Validation**: Validate all addresses (Arweave, Ethereum, Solana formats)
6. **Session Timeout**: 25-minute session limit enforced
7. **HTTPS Only**: All API calls over HTTPS
8. **No Sensitive Logging**: Never log private keys, full addresses in production

---

## Appendix: Reference Implementation

See `c:/source/turbo-app` for the reference implementation:

| Feature | File |
|---------|------|
| Multi-wallet providers | `src/providers/WalletProviders.tsx` |
| Token selection | `src/components/topup/TopUpPanel.tsx` |
| Payment execution | `src/components/topup/CryptoConfirmationPanel.tsx` |
| Balance fetching | `src/hooks/useTokenBalance.ts` |
| Address validation | `src/utils/addressValidation.ts` |
| Token configuration | `src/constants.ts` |
| Network switching | `src/components/topup/CryptoConfirmationPanel.tsx:234-408` |
| Manual payment fallback | `src/components/topup/CryptoManualPaymentPanel.tsx` |
