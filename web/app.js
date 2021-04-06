
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
    //window.addEventListener("arweaveWalletLoaded", async () => {
    if (typeof window.arweaveWallet != 'undefined') {
        await window.arweaveWallet.connect(permissions);
        walletAddress = await window.arweaveWallet.getActiveAddress();
        walletName = await window.arweaveWallet.getWalletNames([walletAddress]);
        
        window.state = { wallet: walletObj };
        console.log('Arweave wallet loaded.')
    }
    //})
}


