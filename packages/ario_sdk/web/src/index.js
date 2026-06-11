import { ARIO, MAINNET_RPC_URL, createCircuitBreakerRpc, defaultFallbackUrl, mARIOToken } from '@ar.io/sdk';

let ario;
try {
  const rpc = createCircuitBreakerRpc({
    primaryUrl: MAINNET_RPC_URL,
    fallbackUrl: defaultFallbackUrl,
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
};

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
