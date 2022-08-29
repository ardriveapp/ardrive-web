import Arweave from 'arweave';
// Import smartweave functions individually to aid Rollup treeshaking.
import { readContract as readSmartweaveContract } from 'smartweave/lib/contract-read';

// Initialise an Arweave client using the default options.
const arweave = Arweave.init({
  host: 'arweave.net',
  port: 443,
  protocol: 'https',
  logging: false,
});

export async function readContractAsStringPromise(
  contractId: string,
): Promise<unknown> {
  const contract = await readSmartweaveContract(arweave, contractId);
  return JSON.stringify(contract);
}
