import { LoggerFactory, WarpFactory, defaultCacheOptions } from 'warp-contracts';


async function readContractAsStringPromise(
  contractId
) {
  LoggerFactory.INST.logLevel('error');
  const warp = WarpFactory.forMainnet({ ...defaultCacheOptions }, true);
  const contract = warp.contract(contractId);
  const { sortKey, cachedValue } = await contract.readState();

  return JSON.stringify({
    contractTxId: contractId,
    state: cachedValue.state,
    sortKey,
  });
}

window.pst = {
  readContractAsStringPromise
}
