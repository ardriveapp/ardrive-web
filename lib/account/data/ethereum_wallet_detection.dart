import 'ethereum_wallet_detection_stub.dart'
    if (dart.library.html) 'ethereum_wallet_detection_web.dart'
    as implementation;

/// Whether MetaMask itself is this browser's Ethereum wallet, not another
/// wallet that also answers to `isMetaMask` (Coinbase Wallet, Brave). Read
/// from the crypto wallet bridge; false where there is none.
bool metaMaskDetected() => implementation.metaMaskDetected();
