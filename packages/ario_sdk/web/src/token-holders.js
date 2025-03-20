/**
 * Currently using the ARIO contract to fetch token holders.
 * This will be updated in the future to use a different contract/process
 * once the migration is complete.
 *
 * Note: This is a temporary implementation and the contract address,
 * pagination, and response format may change.
 */
async function getArDriveTokenHolders() {
  let cursor = null;
  let allBalances = [];
  const limit = 1000;

  const ardriveProcess = new AOProcess({
    // TODO: Update this to the new process ID once the migration is complete
    processId: 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
    ao: connect({ CU_URL: "https://cu.ardrive.io" })
  });

  const paginationParams = [
    { name: "Cursor", value: cursor?.toString() },
    { name: "Limit", value: limit?.toString() },
    { name: "Sort-By", value: "balance" },
    { name: "Sort-Order", value: "desc" }
  ];

  while (true) {
    const response = await ardriveProcess.read({
      tags: [
        { name: 'Action', value: 'Paginated-Balances' },
        ...pruneTags(paginationParams)
      ]
    });

    console.log('Response:', JSON.stringify(response));

    // Add the retrieved balances to the array
    allBalances = allBalances.concat(response.items);

    // TODO: I'm just using so we dont need to wait for all the balances to be fetched
    // it's just a test
    if (allBalances.length > 1000) {
      break;
    }

    // Break the loop if there are no more balances to fetch
    if (!response.items.length || !response.nextCursor) {
      break;
    }

    // Set the cursor for the next request
    cursor = response.nextCursor;
  }

  return JSON.stringify(allBalances);
}