const permissions = [
  'ACCESS_ADDRESS',
  'SIGN_TRANSACTION',
  'SIGNATURE',
  'ACCESS_PUBLIC_KEY',
  'ACCESS_ALL_ADDRESSES',
];

function isExtensionPresent() {
  return window.arweaveWallet != null && window.arweaveWallet != 'undefined';
}

async function connect() {
  return await window.arweaveWallet.connect(permissions);
}

async function checkPermissions() {
  var acceptedPermissions = await window.arweaveWallet.getPermissions();
  return permissions.every(i => acceptedPermissions.includes(i));
}

async function disconnect() {
  return await window.arweaveWallet.disconnect();
}

async function listenForWalletSwitch() {
  window.addEventListener('walletSwitch', () => {
    window.parent.postMessage('walletSwitch', '*');
  });
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
