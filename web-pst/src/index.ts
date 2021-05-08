import Arweave from 'arweave';
// Import smartweave functions individually to aid Rollup treeshaking.
import { readContract } from 'smartweave/lib/contract-read';

// Initialise an Arweave client using the default options.
const arweave = Arweave.init({
  host: 'arweave.net',
  port: 443,
  protocol: 'https',
  logging: false,
});

const pstContractId = '-8A6RexFkpfWwuyVO98wzSFZh0d6VJuI-buTJvlwOJQ';

// Read the PST contract state and cache it for the life of the script.
const pstContractStateRead = readContract(arweave, pstContractId);
// Start loading the contract state early so the functions above can access the state faster.
(async () => {
  await pstContractStateRead;
})();
export function weightedRandom(
  dict: Record<string, number>,
): string | undefined {
  let sum = 0;
  const r = Math.random();
  for (const addr of Object.keys(dict)) {
    sum += dict[addr];
    if (r <= sum && dict[addr] > 0) {
      return addr;
    }
  }
  return;
}

export async function getWeightedPstHolder(): Promise<string | undefined> {
  const state = await pstContractStateRead;
  const balances = state.balances;
  const vault = state.vault;

  let total = 0;
  for (const addr of Object.keys(balances)) {
    total += balances[addr];
  }
  for (const addr of Object.keys(vault)) {
    if (!vault[addr].length) continue;
    const vaultBalance = vault[addr]
      .map((a: { balance: number; start: number; end: number }) => a.balance)
      .reduce((a: number, b: number) => a + b, 0);
    total += vaultBalance;
    if (addr in balances) {
      balances[addr] += vaultBalance;
    } else {
      balances[addr] = vaultBalance;
    }
  }
  const weighted: { [addr: string]: number } = {};
  for (const addr of Object.keys(balances)) {
    weighted[addr] = balances[addr] / total;
  }
  const randomHolder = weightedRandom(weighted);
  return randomHolder;
}

export async function getPstFeePercentage(): Promise<number> {
  const contractState = await pstContractStateRead;
  const feeSetting = contractState.settings.find(
    (setting: { toString: () => string }[]) =>
      setting[0].toString().toLowerCase() === 'fee',
  );
  return feeSetting[1] / 100;
}
