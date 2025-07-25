import { ANT, ANT_REGISTRY_ID, ANTRegistry, AOProcess, ArconnectSigner, ARIO, ArNSEventEmitter, ArweaveSigner, mARIOToken } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';

window.ario = {
  getGateways,
  getARIOTokens,
  setARNS,
  setAnt,
  getUndernames,
  getARNSRecordsForWallet,
  getPrimaryNameAndLogo,
};

const ario = ARIO.init({
  process: new AOProcess({
    processId: 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
    ao: connect({
      CU_URL: 'https://cu.ardrive.io'
    })
  }),
});

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

async function getARIOTokens(address) {
  try{
    const balance = await ario
      .getBalance({
        address: address,
      })
      .then((balance) => new mARIOToken(balance).toARIO());

    return balance;
  } catch(e) {
    console.error(e);
  }
}


async function setAnt(JWKString, processId, txId, undername, useArConnect, ttlSeconds = 900) {
  const signer = useArConnect ? new ArconnectSigner(window.arweaveWallet) : new ArweaveSigner(JSON.parse(JWKString));

  const ant = ANT.init({
    signer: signer,
    process: new AOProcess({
      processId: processId,
      ao: connect({ CU_URL: "https://cu.ardrive.io" })
    })
  });

  const { id } = await ant.setRecord(
    {
      undername: undername,
      transactionId: txId,
      ttlSeconds: ttlSeconds
    },

  { tags: [{ name: 'App-Name', value: 'ArDrive-App' }] },
  );

  return id;
}

async function setARNS(JWKString, txId, domain, undername, useArConnect, ttlSeconds = 900) {
  try {
    const record = await ario.getArNSRecord({ name: domain });

    const processId = record.processId;

    const setRecordResult = await setAnt(JWKString, processId, txId, undername, useArConnect, ttlSeconds);

    return JSON.stringify(setRecordResult);
  } catch (error) {
    console.error('Error in setARNS:', error);
    throw error;
  }
}

async function getUndernames(JWKString, processId) {
  const ant = ANT.init({
    signer: new ArweaveSigner(JSON.parse(JWKString)),
    process: new AOProcess({
      processId: processId,
      ao: connect({ CU_URL: "https://cu.ardrive.io" })
    })
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
      contract: ario,
      antAoClient: connect({ CU_URL: "https://cu.ardrive.io" })
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
      pageSize: 1000,
      antRegistry: ANTRegistry.init({
        process: new AOProcess({
          processId: ANT_REGISTRY_ID,
          ao: connect({ CU_URL: "https://cu.ardrive.io" })
        })
      })
    });
  });
}

async function getPrimaryNameAndLogo(address, getLogo = true) {
  let primaryName;

  try {
     primaryName = await ario.getPrimaryName({ address: address });
  } catch(e) {
    console.error('Error fetching primary name:', e);
  }

  var info = null;
  var record = null;

  if (getLogo && primaryName && primaryName.name) {
    try {
      record = await ario.getArNSRecord({ name: primaryName.name });
      if (record && record.processId) {
        const ant = ANT.init({
          process: new AOProcess({
            processId: record.processId,
            ao: connect({ CU_URL: "https://cu.ardrive.io" })
          })
        });
        info = await ant.getInfo();
      }
    } catch(e) {
      console.error('Error fetching logo info:', e);
    }
  }

  return JSON.stringify({
    primaryName: primaryName,
    antInfo: info,
    arnsRecord: record
  });
}
