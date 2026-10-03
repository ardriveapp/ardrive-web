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
  console.log('[ArConnect] Required permissions:', permissions);
  console.log('[ArConnect] Accepted permissions:', acceptedPermissions);
  const hasAll = permissions.every(i => acceptedPermissions.includes(i));
  console.log('[ArConnect] Has all required permissions:', hasAll);
  return hasAll;
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
  console.log('[ArConnect] getSignature called with', message.length, 'bytes');
  try {
    var input = new Uint8Array(message);
    console.log('[ArConnect] Calling arweaveWallet.signature()...');
    var response = await window.arweaveWallet.signature(input, {
      name: 'RSA-PSS',
      saltLength: 0,
    });
    console.log('[ArConnect] signature() returned:', typeof response, response);
    var array = Uint8Array.from(Object.values(response));
    console.log('[ArConnect] getSignature successful, returning', array.length, 'bytes');
    return array;
  } catch (e) {
    console.error('[ArConnect] getSignature FAILED:', e);
    throw e;
  }
}

async function signDataItem(data, tags, owner, target, anchor) {
  console.log('[ArConnect] signDataItem called with', data.length, 'bytes');
  console.log('[ArConnect] tags:', tags);
  try {
    // Tags come from Dart as base64-encoded strings, decode them for Wander
    const jsTags = tags.map(tag => ({
      name: atob(tag.name),
      value: atob(tag.value),
    }));
    console.log('[ArConnect] decoded tags:', jsTags);

    const jsDataItem = {
      owner: owner,
      target: target,
      anchor: anchor,
      data: data,
      tags: jsTags,
    };
    console.log('[ArConnect] Calling arweaveWallet.signDataItem()...');
    var signed = await window.arweaveWallet.signDataItem(jsDataItem, { saltLength: 0});
    console.log('[ArConnect] signDataItem() returned:', typeof signed, signed?.length || signed);

    // Signature stored after first two bytes, and arweave sig length is 512
    var signature = signed.slice(2, 514);
    console.log('[ArConnect] signDataItem successful, returning', signature.length, 'bytes');

    return new Uint8Array(signature);
  } catch (e) {
    console.error('[ArConnect] signDataItem FAILED:', e);
    throw e;
  }
}

async function getWalletVersion() {
  return await window.arweaveWallet.walletVersion;
}