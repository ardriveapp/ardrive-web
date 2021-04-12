
const permissions = [
    "ACCESS_ADDRESS",
    "ACCESS_ALL_ADDRESSES",
    "SIGN_TRANSACTION",
    "ENCRYPT",
    "DECRYPT",
    "SIGNATURE",
];



async function loadWallet() {
    var walletAddress;
    var walletName;
    var signature;
    //Have to use this because the window.arweaveWalletLoaded listener does not work for some reason
    if (typeof window.arweaveWallet != 'undefined') {
        await window.arweaveWallet.connect(permissions);
        walletAddress = await window.arweaveWallet.getActiveAddress();
        walletName = await window.arweaveWallet.getWalletNames([walletAddress]);
        
        console.log('Arweave wallet loaded.')
        console.log(walletAddress);
        console.log(walletName);
        return { 'walletAddress': walletAddress, 'walletName': walletName };
    }

    return {};



}


