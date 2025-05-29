const permissions = [
  'ACCESS_ADDRESS',
  'SIGN_TRANSACTION',
  'SIGNATURE',
  'ACCESS_PUBLIC_KEY',
  'ACCESS_ALL_ADDRESSES',
];

const appInfo = {
  logo: 'https://app.ardrive.io/favicon.png',
  name: 'ArDrive',
}

function isExtensionPresent() {
  return window.arweaveWallet != null && window.arweaveWallet != 'undefined';
}

async function connect() {
  return await window.arweaveWallet.connect(permissions, appInfo);
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

async function signDataItem(data, tags, owner, target, anchor) {
  const jsTags = tags.map(tag => ({
    name: atob(tag.name),
    value: atob(tag.value),
  }));

  const jsDataItem = {
    owner: owner,
    target: target,
    anchor: anchor,
    data: data,
    tags: jsTags,
  };
  var signed = await window.arweaveWallet.signDataItem(jsDataItem, { saltLength: 0});

  // Signature stored after first two bytes, and arweave sig length is 512
  var signature = signed.slice(2, 514);

  return new Uint8Array(signature);
}

async function getWalletVersion() {
  return await window?.arweaveWallet?.walletVersion ?? null;
}