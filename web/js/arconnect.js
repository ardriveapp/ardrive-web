const permissions = [
    "ACCESS_ADDRESS",
    "ACCESS_ALL_ADDRESSES",
    "SIGN_TRANSACTION",
    "ENCRYPT",
    "DECRYPT",
    "SIGNATURE",
];


function isExtensionPresent() {
    return window.arweaveWallet != null && window.arweaveWallet != 'undefined';
}

async function connect() {
    return await window.arweaveWallet.connect(permissions);
}

async function getWalletAddress() {
    return await window.arweaveWallet.getActiveAddress();
}

async function getSignature(message) {
    return await window.arweaveWallet.signature(
        {
            data: message,
            options: {
                algorithm: "sha256",
                signing: { padding: 6, saltLength: 0 }
            }
        }
    );


}





