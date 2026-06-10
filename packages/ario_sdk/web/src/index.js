import { ARIO, MAINNET_RPC_URL, mARIOToken } from '@ar.io/sdk';
import { createSolanaRpc } from '@solana/kit';

const rpc = createSolanaRpc(MAINNET_RPC_URL);
const ario = ARIO.init({ rpc });

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
