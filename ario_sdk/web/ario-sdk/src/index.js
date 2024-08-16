import { ANT, ArweaveSigner, IO, mIOToken } from '@ar.io/sdk';

// async function getAllGateways(limit = 100, sortBy = 'operatorStake', sortOrder = 'desc') {
  // const io = IO.init();
//   let allGateways = [];
//   let cursor = null;

//   while (true) {
//     const response = await io.getGateways({
//       cursor: cursor,
//       limit: limit,
//       sortBy: sortBy,
//       sortOrder: sortOrder,
//     });

//     allGateways = allGateways.concat(response.gateways);

//     if (!response.nextCursor) {
//       break;
//     }

//     cursor = response.nextCursor;
//   }

//   return allGateways;
// }

async function getGateways() {
  const io = IO.init();

  const gateways = await io.getGateways({
      // limit: 100,
      sortOrder: 'desc',
      sortBy: 'operatorStake',
    });

  return JSON.stringify(gateways);
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
  }catch(e) {
    console.error(e);
  }
}

window.ario = {
  getGateways,
  getIOTokens,
  setARNS,
  setAnt,
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

  const processId = record.processId;

  const setRecordResult = await setAnt(JWKString, processId, txId, undername);

  return JSON.stringify(setRecordResult);
}

async function getARNSRecord(JWKString, domain) {
  // const io = IO.init({ signer: new ArweaveSigner(JSON.parse(JWKString)) });
  const io = IO.init();
  
  const record = await io.getArNSRecord({ name: domain });

  console.log(record);

  return JSON.stringify(record);
}


