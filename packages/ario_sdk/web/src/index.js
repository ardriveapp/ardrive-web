import { ANT, ArweaveSigner, IO, mIOToken } from '@ar.io/sdk';

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

    console.log(response);

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
  setARNS,
  setAnt,
  getUndernames,
  getARNSRecord,
};


async function setAnt(JWKString, processId, txId, undername) {
  const ant = ANT.init({
    signer: new ArweaveSigner(JSON.parse(JWKString)),
    processId: processId,
  });

  const { id } = await ant.setRecord(
    {
      undername: undername,
      transactionId: txId,
      ttlSeconds: 3600
    },

  { tags: [{ name: 'App-Name', value: 'ArDrive-App' }] },
  );

  return id;
}

async function setARNS(JWKString, txId, domain, undername) {
  const io = IO.init();
  const record = await io.getArNSRecord({ name: domain });

  console.log(record);

  const processId = record.processId;

  console.log('TransationId : ' + txId);

  const setRecordResult = await setAnt(JWKString, processId, txId, undername);

  return JSON.stringify(setRecordResult);
}

async function getARNSRecord(JWKString, domain) {
  const io = IO.init();

  const record = await io.getArNSRecord({ name: domain });

  return JSON.stringify(record);
}

async function getUndernames(JWKString, processId) {
  const ant = ANT.init({
    signer: new ArweaveSigner(JSON.parse(JWKString)),
    processId: processId,
  });

  const records = await ant.getRecords();

  return JSON.stringify(records);
}


