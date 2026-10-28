/// Chain ID to network name mapping
String getNetworkName(int chainId) {
  switch (chainId) {
    case 1:
      return 'Ethereum Mainnet';
    case 8453:
      return 'Base';
    case 11155111:
      return 'Sepolia (Testnet)';
    case 84532:
      return 'Base Sepolia (Testnet)';
    default:
      return 'Unknown network';
  }
}
