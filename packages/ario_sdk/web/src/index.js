import {
  ARIO,
  MAINNET_RPC_URL,
  DEVNET_RPC_URL,
  MAINNET_PROGRAM_IDS,
  DEVNET_PROGRAM_IDS,
  createCircuitBreakerRpc,
  defaultFallbackUrl,
  mARIOToken,
} from '@ar.io/sdk';

// Public Solana RPC (api.mainnet-beta.solana.com) returns 403 from browsers.
// Use ArDrive's managed QuickNode RPC (same as turbo/crypto_network_config.dart).
const ARDRIVE_MAINNET_RPC = 'https://damp-stylish-sheet.solana-mainnet.quiknode.pro/b3dd2ce1c4f1a06d5fb6c42b80d6848796dd6408/';
const ARDRIVE_DEVNET_RPC = 'https://api.devnet.solana.com';

let ario;
try {
  const rpc = createCircuitBreakerRpc({
    primaryUrl: ARDRIVE_MAINNET_RPC,
    fallbackUrl: defaultFallbackUrl(ARDRIVE_MAINNET_RPC),
  });
  ario = ARIO.init({ rpc });
} catch (e) {
  console.error('[ario_sdk] Failed to initialize ARIO SDK:', e);
}

window.ario = {
  getGateways,
  getARIOTokens,
  setARNS,
  setAnt,
  getUndernames,
  getARNSRecordsForWallet,
  getPrimaryNameAndLogo,
  reinitArioSDK,
  getArioConfig,
};

async function reinitArioSDK(rpcUrl, coreProgramId, garProgramId, arnsProgramId, antProgramId) {
  const url = rpcUrl || ARDRIVE_MAINNET_RPC;
  const rpc = createCircuitBreakerRpc({
    primaryUrl: url,
    fallbackUrl: defaultFallbackUrl(url),
  });

  const config = { rpc };
  if (coreProgramId) config.coreProgramId = coreProgramId;
  if (garProgramId) config.garProgramId = garProgramId;
  if (arnsProgramId) config.arnsProgramId = arnsProgramId;
  if (antProgramId) config.antProgramId = antProgramId;

  ario = ARIO.init(config);
  console.log('[ario_sdk] Reinitialized with RPC:', url);
  return true;
}

function getArioConfig() {
  return JSON.stringify({
    mainnetRpcUrl: ARDRIVE_MAINNET_RPC,
    devnetRpcUrl: ARDRIVE_DEVNET_RPC,
    mainnetProgramIds: MAINNET_PROGRAM_IDS,
    devnetProgramIds: DEVNET_PROGRAM_IDS,
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

// Stub functions - ArNS write operations require Solana signers (future PR)
async function setAnt() {
  throw new Error('ANT operations not yet implemented for Solana');
}

async function setARNS() {
  throw new Error('ArNS operations not yet implemented for Solana');
}

async function getUndernames() {
  throw new Error('Undername operations not yet implemented for Solana');
}

async function getARNSRecordsForWallet() {
  throw new Error('ArNS records not yet implemented for Solana');
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
