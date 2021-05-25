const permissions = [
  'ACCESS_ADDRESS',
  'ACCESS_ALL_ADDRESSES',
  'SIGN_TRANSACTION',
  'ENCRYPT',
  'DECRYPT',
  'SIGNATURE',
  'ACCESS_PUBLIC_KEY',
];

function isExtensionPresent() {
  return window.arweaveWallet != null && window.arweaveWallet != 'undefined';
}

async function connect() {
  return await window.arweaveWallet.connect(permissions);
}

async function disconnect() {
  return await window.arweaveWallet.disconnect();
}



async function getWalletAddress() {
  return await window.arweaveWallet.getActiveAddress();
}

async function getPublicKey() {
  return await window.arweaveWallet.getActivePublicKey();
}

async function getSignature(message) {
  var input = new Uint8Array(message);
  var response = await window.arweaveWallet.signature(input, {
    name: 'RSA-PSS',
    saltLength: 0,
  });
  var array = Uint8Array.from(Object.values(response));
  return array;
}
