import Arweave from 'arweave';
// Import smartweave functions individually to aid Rollup treeshaking.
import { readContract } from 'smartweave/lib/contract-read';
import { selectWeightedPstHolder } from 'smartweave/lib/weighted-pst-holder';

// Initialise an Arweave client using the default options.
const arweave = Arweave.init({
  host: 'arweave.net',
  port: 443,
  protocol: 'https',
});

const pstContractId = '-8A6RexFkpfWwuyVO98wzSFZh0d6VJuI-buTJvlwOJQ';

// Read the PST contract state and cache it for the life of the script.
const pstContractStateRead = readContract(arweave, pstContractId);

export async function getWeightedPstHolder(): Promise<String> {
  // Select a PST holder from the cached PST contract state.
  const contractState = await pstContractStateRead;
  return selectWeightedPstHolder(contractState.balances);
}
