import { ANT, AOProcess, ArNSEventEmitter, ArweaveSigner, IO, IO_TESTNET_PROCESS_ID, mIOToken } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';

window.ario = {
  getGateways,
  getIOTokens,
  setARNS,
  setAnt,
  getUndernames,
  getARNSRecordsForWallet,
};

const io = IO.init({
  process: new AOProcess({
    processId: IO_TESTNET_PROCESS_ID,
    ao: connect({
      CU_URL: 'https://cu.ar-io.dev'
    })
  }),
});

async function getGateways() {
  let cursor = null;
  let allGateways = [];
  const limit = 100;

  while (true) {
    const response = await io.getGateways({
      cursor: cursor,
      limit: limit,
      sortOrder: 'desc',
      sortBy: 'operatorStake',
    });

    // Add the retrieved gateways to the array
    allGateways = allGateways.concat(response.items);

    // Break the loop if there are no more gateways to fetch
    if (!response.items.length || !response.nextCursor) {
      break;
    }

    // Set the cursor to the last gateway address for the next request
    cursor = response.nextCursor;
  }

  return JSON.stringify(allGateways);
}

async function getIOTokens(address) {
  try{
    // the balance will be returned in mIO as a value
    const balance = await io
      .getBalance({
        address: address,
      })
      .then((balance) => new mIOToken(balance).toIO());

    return balance;
  } catch(e) {
    console.error(e);
  }
}



async function setAnt(JWKString, processId, txId, undername) {
  const ant = ANT.init({
    signer: new ArweaveSigner(JSON.parse(JWKString)),
    processId: processId
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
  const record = await io.getArNSRecord({ name: domain });

  console.log(record);

  const processId = record.processId;

  const setRecordResult = await setAnt(JWKString, processId, txId, undername);

  return JSON.stringify(setRecordResult);
}

async function getUndernames(JWKString, processId) {
  const ant = ANT.init({
    signer: new ArweaveSigner(JSON.parse(JWKString)),
    processId: processId,
  });

  const records = await ant.getRecords();

  return JSON.stringify(records);
}

async function getARNSRecordsForWallet(address) {
  try {
    console.log('Fetching processes for wallet:', address);
    const jsonResult = await getProcesses(address);
    console.log('JSON Result:', jsonResult);
    return jsonResult;
  } catch (error) {
    console.error('Failed to fetch processes:', error);
    throw error;
  }
}

async function getProcesses(address) {
  return new Promise((resolve, reject) => {
    // Initialize the emitter
    console.log('Initializing emitter');

    const arnsEmitter = new ArNSEventEmitter({
      timeoutMs: 60000,
      concurrency: 10,
      contract: io,
    });

    arnsEmitter.on('progress', (current, total) => {
      console.log(`Progress: ${current}/${total}`);
    });

    arnsEmitter.on('process', (processId, processData) => {
      console.log(`Process ${processId} details:`, processData);
    });

    arnsEmitter.on('error', (error) => {
      console.error('Error:', error);
      reject(error);
    });

    arnsEmitter.on('end', (result) => {
      console.log('Completed fetching processes:', result);
      resolve(JSON.stringify(result));
    });

    arnsEmitter.fetchProcessesOwnedByWallet({
      address: address,
      pageSize: 100
    });
  });
}
