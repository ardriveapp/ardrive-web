import { IO, mIOToken } from '@ar.io/sdk';

async function getGateways() {
  const io = IO.init();
  let cursor = null;
  let allGateways = [];
  const limit = 100; // Adjust the limit as needed

  while (true) {
    const response = await io.getGateways({
      cursor: cursor,
      limit: limit,
      sortOrder: 'desc',
      sortBy: 'operatorStake',
    });

    // Add the retrieved gateways to the array
    allGateways = allGateways.concat(response.gateways);

    // Break the loop if there are no more gateways to fetch
    if (!response.gateways.length || !response.nextCursor) {
      break;
    }

    // Set the cursor to the last gateway address for the next request
    cursor = response.nextCursor;
  }

  console.log(allGateways.length);

  return JSON.stringify(allGateways);
}

async function getIOTokens(address) {
  try{
    console.log(address);
  const io = IO.init();
  // the balance will be returned in mIO as a value
  const balance = await io
    .getBalance({
      address: address,
    })
    .then((balance) => new mIOToken(balance).toIO());

  console.log(balance);

  return balance;
  } catch(e) {
    console.error(e);
  }
}

window.ario = {
  getGateways,
  getIOTokens,
};
