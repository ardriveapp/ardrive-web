import Arweave from 'arweave';
// Import smartweave functions individually to aid Rollup treeshaking.
import { readContract } from 'smartweave/lib/contract-read';
import { selectWeightedPstHolder } from 'smartweave/lib/weighted-pst-holder';
import { Contract } from './contract';

// Initialise an Arweave client using the default options.
const arweave = Arweave.init({
  host: 'arweave.net',
  port: 443,
  protocol: 'https',
  logging: false,
});

const pstContractId = '-8A6RexFkpfWwuyVO98wzSFZh0d6VJuI-buTJvlwOJQ';

// Read the PST contract state and cache it for the life of the script.
const pstContractStateRead = readContract(
  arweave,
  pstContractId,
) as Promise<Contract>;

export async function getPstFeePercentage(): Promise<number> {
  const contractState = await pstContractStateRead;
  const feeSetting = contractState.settings.find(
    (setting) => setting[0].toString().toLowerCase() === 'fee',
  );
  return feeSetting[1] / 100;
}

export async function getWeightedPstHolder(): Promise<String> {
  // Select a PST holder from the cached PST contract state.
  const contractState = await pstContractStateRead;
  return selectWeightedPstHolder(contractState.balances);
}

// Start loading the contract state early so the functions above can access the state faster.
(async () => {
  await pstContractStateRead;
})();
