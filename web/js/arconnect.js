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
    var response =
        await window.arweaveWallet.signature(
            message,
            {
                name: "RSA-PSS",
                saltLength: 32,
            }
        );
    console.log(response);
    return response;

}





