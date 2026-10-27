import {
  ARIO,
  MAINNET_PROGRAM_IDS,
  DEVNET_PROGRAM_IDS,
  createCircuitBreakerRpc,
  mARIOToken,
} from '@ar.io/sdk';

import * as arns from './arns.js';
import * as wallet from './wallet.js';

// Public Solana RPC (api.mainnet-beta.solana.com) returns 403 from browsers.
// Use ArDrive's managed QuickNode RPC (same as turbo/crypto_network_config.dart).
// No public fallback: a degraded primary fails rather than moving ArDrive's
// traffic onto shared infrastructure.
const ARDRIVE_MAINNET_RPC = 'https://damp-stylish-sheet.solana-mainnet.quiknode.pro/b3dd2ce1c4f1a06d5fb6c42b80d6848796dd6408/';
const ARDRIVE_DEVNET_RPC = 'https://api.devnet.solana.com';

let ario;
let rpc;
let rpcUrl = ARDRIVE_MAINNET_RPC;
let antProgramId = null;

function init(config) {
  rpc = createCircuitBreakerRpc({ primaryUrl: rpcUrl });
  ario = ARIO.init({ rpc, ...config });
}

try {
  init({});
} catch (e) {
  console.error('[ario_sdk] Failed to initialize ARIO SDK:', e);
}

function isDevnet() {
  return /devnet/i.test(rpcUrl) || antProgramId === DEVNET_PROGRAM_IDS.ant;
}

const ctx = {
  ario: () => {
    if (!ario) throw new Error('ARIO SDK not initialized');
    return ario;
  },
  rpc: () => rpc,
  rpcUrl: () => rpcUrl,
  antProgramId: () => antProgramId,
  antProgramIdOrDefault: () => antProgramId ?? MAINNET_PROGRAM_IDS.ant,
  chain: () => (isDevnet() ? 'solana:devnet' : 'solana:mainnet'),
};

window.ario = {
  getGateways,
  getARIOTokens,
  getPrimaryNameAndLogo,
  reinitArioSDK,
  getArioConfig,

  listSolanaWallets: wallet.listSolanaWallets,
  connectSolanaWallet: wallet.connectSolanaWallet,
  disconnectSolanaWallet: wallet.disconnectSolanaWallet,
  connectedSolanaAddress: wallet.connectedSolanaAddress,
  connectedSolanaWalletName: wallet.connectedSolanaWalletName,
  setSolanaAccountListener: wallet.setSolanaAccountListener,
  setSolanaWalletsListener: wallet.setSolanaWalletsListener,
  solanaSignMessage: wallet.solanaSignMessage,
  solanaSignTransaction: (tx) => wallet.solanaSignTransaction(tx, ctx.chain()),

  getArNSNamesForAddress: (owner) => arns.getArNSNamesForAddress(ctx, owner),
  getANTSummaries: (ids) => arns.getANTSummaries(ctx, ids),
  getANTRecords: (processId) => arns.getANTRecords(ctx, processId),
  setRecordAsController: (processId, undername, transactionId, ttlSeconds) =>
    arns.setRecordAsController(
      ctx,
      processId,
      undername,
      transactionId,
      ttlSeconds,
    ),
  removeRecordAsController: (processId, undername) =>
    arns.removeRecordAsController(ctx, processId, undername),
  getSolBalanceLamports: (owner) => arns.getSolBalanceLamports(ctx, owner),
  estimateControllerFee: (processId, workflow, undername) =>
    arns.estimateControllerFee(ctx, processId, workflow, undername),
};

async function reinitArioSDK(newRpcUrl, coreProgramId, garProgramId, arnsProgramId, newAntProgramId) {
  rpcUrl = newRpcUrl || ARDRIVE_MAINNET_RPC;
  antProgramId = newAntProgramId || null;

  const config = {};
  if (coreProgramId) config.coreProgramId = coreProgramId;
  if (garProgramId) config.garProgramId = garProgramId;
  if (arnsProgramId) config.arnsProgramId = arnsProgramId;
  if (newAntProgramId) config.antProgramId = newAntProgramId;

  init(config);
  console.log('[ario_sdk] Reinitialized with RPC:', rpcUrl);
  return true;
}

function getArioConfig() {
  return JSON.stringify({
    mainnetRpcUrl: ARDRIVE_MAINNET_RPC,
    devnetRpcUrl: ARDRIVE_DEVNET_RPC,
    mainnetProgramIds: MAINNET_PROGRAM_IDS,
    devnetProgramIds: DEVNET_PROGRAM_IDS,
    isDevnet: isDevnet(),
  });
}

async function getGateways() {
  if (!ario) throw new Error('ARIO SDK not initialized');

  let cursor = null;
  let allGateways = [];
  const limit = 1000;

  while (true) {
    const response = await ario.getGateways({
      cursor: cursor,
      limit: limit,
      sortOrder: 'desc',
      sortBy: 'operatorStake',
    });

    allGateways = allGateways.concat(response.items);

    if (!response.items.length || !response.nextCursor) {
      break;
    }

    cursor = response.nextCursor;
  }

  // Sort by total stake (operator + delegated) descending
  allGateways.sort((a, b) =>
    (b.operatorStake + b.totalDelegatedStake) - (a.operatorStake + a.totalDelegatedStake)
  );

  return JSON.stringify(allGateways);
}

async function getARIOTokens(address) {
  if (!ario) throw new Error('ARIO SDK not initialized');

  try {
    const balance = await ario
      .getBalance({
        address: address,
      })
      .then((balance) => new mARIOToken(balance).toARIO());

    return balance;
  } catch (e) {
    console.error(e);
  }
}

async function getPrimaryNameAndLogo(address, getLogo = true) {
  if (!ario) {
    return JSON.stringify({ primaryName: null, antInfo: null, arnsRecord: null });
  }

  let primaryName;

  try {
    primaryName = await ario.getPrimaryName({ address: address });
  } catch (e) {
    console.error('Error fetching primary name:', e);
  }

  if (!primaryName) {
    return JSON.stringify({
      primaryName: null,
      antInfo: null,
      arnsRecord: null,
    });
  }

  // ANT info (logo) requires Solana ANT integration (future PR)
  return JSON.stringify({
    primaryName: primaryName,
    antInfo: null,
    arnsRecord: null,
  });
}
