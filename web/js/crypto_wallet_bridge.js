/**
 * Crypto Wallet Bridge
 *
 * Provides a unified JavaScript API for connecting to Ethereum and Solana wallets.
 * This bridge is called from Dart via JS interop.
 */

(function() {
  'use strict';

  // ============================================
  // Ethereum Wallet Detection & Connection
  // ============================================

  /**
   * Detect available Ethereum wallet providers
   * @returns {Object} Object with detected providers
   */
  function detectEthereumProviders() {
    const providers = {
      hasAnyProvider: false,
      metamask: false,
      coinbaseWallet: false,
      rainbow: false,
      trust: false,
      brave: false,
      generic: false,
    };

    if (typeof window.ethereum !== 'undefined') {
      providers.hasAnyProvider = true;
      providers.generic = true;

      // Check for specific wallet flags
      if (window.ethereum.isMetaMask) {
        providers.metamask = true;
      }
      if (window.ethereum.isCoinbaseWallet) {
        providers.coinbaseWallet = true;
      }
      if (window.ethereum.isRainbow) {
        providers.rainbow = true;
      }
      if (window.ethereum.isTrust) {
        providers.trust = true;
      }
      if (window.ethereum.isBraveWallet) {
        providers.brave = true;
      }

      // Handle multiple providers (EIP-6963)
      if (window.ethereum.providers && Array.isArray(window.ethereum.providers)) {
        for (const provider of window.ethereum.providers) {
          if (provider.isMetaMask) providers.metamask = true;
          if (provider.isCoinbaseWallet) providers.coinbaseWallet = true;
          if (provider.isRainbow) providers.rainbow = true;
        }
      }
    }

    return providers;
  }

  /**
   * Get the Ethereum provider, optionally preferring a specific one
   * @param {string} preferred - Preferred provider: 'metamask', 'coinbase', etc.
   * @returns {Object|null} The provider or null if not found
   */
  function getEthereumProvider(preferred) {
    if (typeof window.ethereum === 'undefined') {
      return null;
    }

    // If multiple providers exist (EIP-6963), try to find the preferred one
    if (window.ethereum.providers && Array.isArray(window.ethereum.providers)) {
      for (const provider of window.ethereum.providers) {
        if (preferred === 'metamask' && provider.isMetaMask && !provider.isCoinbaseWallet) {
          return provider;
        }
        if (preferred === 'coinbase' && provider.isCoinbaseWallet) {
          return provider;
        }
        if (preferred === 'rainbow' && provider.isRainbow) {
          return provider;
        }
      }
    }

    // Return the default provider
    return window.ethereum;
  }

  /**
   * Connect to an Ethereum wallet
   * @param {string} providerPreference - Optional: 'metamask', 'coinbase', etc.
   * @returns {Promise<Object>} Connection result with address and chainId
   */
  async function connectEthereumWallet(providerPreference) {
    const provider = getEthereumProvider(providerPreference);

    if (!provider) {
      throw new Error('NO_PROVIDER');
    }

    try {
      // Request account access
      const accounts = await provider.request({ method: 'eth_requestAccounts' });

      if (!accounts || accounts.length === 0) {
        throw new Error('NO_ACCOUNTS');
      }

      // Get current chain ID
      const chainIdHex = await provider.request({ method: 'eth_chainId' });
      const chainId = parseInt(chainIdHex, 16);

      return {
        address: accounts[0],
        chainId: chainId,
        providerType: detectProviderType(provider),
      };
    } catch (error) {
      if (error.code === 4001) {
        throw new Error('USER_REJECTED');
      }
      throw error;
    }
  }

  /**
   * Get connected Ethereum accounts (without prompting)
   * @returns {Promise<string[]>} Array of connected addresses
   */
  async function getEthereumAccounts() {
    const provider = getEthereumProvider();
    if (!provider) return [];

    try {
      const accounts = await provider.request({ method: 'eth_accounts' });
      return accounts || [];
    } catch (e) {
      return [];
    }
  }

  /**
   * Get current Ethereum chain ID
   * @returns {Promise<number>} Chain ID
   */
  async function getEthereumChainId() {
    const provider = getEthereumProvider();
    if (!provider) throw new Error('NO_PROVIDER');

    const chainIdHex = await provider.request({ method: 'eth_chainId' });
    return parseInt(chainIdHex, 16);
  }

  /**
   * Switch Ethereum network
   * @param {number} chainId - Target chain ID
   * @returns {Promise<void>}
   */
  async function switchEthereumChain(chainId) {
    const provider = getEthereumProvider();
    if (!provider) throw new Error('NO_PROVIDER');

    const chainIdHex = '0x' + chainId.toString(16);

    try {
      await provider.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: chainIdHex }],
      });
    } catch (error) {
      // Error code 4902 means the chain is not added to the wallet
      if (error.code === 4902) {
        throw new Error('CHAIN_NOT_ADDED');
      }
      if (error.code === 4001) {
        throw new Error('USER_REJECTED');
      }
      throw error;
    }
  }

  /**
   * Add a new chain to the wallet
   * @param {Object} chainParams - EIP-3085 chain parameters
   * @returns {Promise<void>}
   */
  async function addEthereumChain(chainParams) {
    const provider = getEthereumProvider();
    if (!provider) throw new Error('NO_PROVIDER');

    try {
      await provider.request({
        method: 'wallet_addEthereumChain',
        params: [chainParams],
      });
    } catch (error) {
      if (error.code === 4001) {
        throw new Error('USER_REJECTED');
      }
      throw error;
    }
  }

  /**
   * Get Ethereum balance (native or ERC-20)
   * @param {string} address - Wallet address
   * @param {string} tokenAddress - Optional ERC-20 token address (null for native)
   * @returns {Promise<string>} Balance in smallest unit (wei/token units)
   */
  async function getEthereumBalance(address, tokenAddress) {
    const provider = getEthereumProvider();
    if (!provider) throw new Error('NO_PROVIDER');

    if (!tokenAddress) {
      // Native ETH balance
      const balanceHex = await provider.request({
        method: 'eth_getBalance',
        params: [address, 'latest'],
      });
      return BigInt(balanceHex).toString();
    } else {
      // ERC-20 token balance
      const data = '0x70a08231' + address.slice(2).padStart(64, '0');
      const result = await provider.request({
        method: 'eth_call',
        params: [{ to: tokenAddress, data: data }, 'latest'],
      });
      return BigInt(result).toString();
    }
  }

  /**
   * Estimate gas for a transaction
   * @param {Object} txParams - Transaction parameters
   * @returns {Promise<string>} Gas estimate
   */
  async function estimateEthereumGas(txParams) {
    const provider = getEthereumProvider();
    if (!provider) throw new Error('NO_PROVIDER');

    const gasHex = await provider.request({
      method: 'eth_estimateGas',
      params: [txParams],
    });
    return BigInt(gasHex).toString();
  }

  /**
   * Get current gas price
   * @returns {Promise<string>} Gas price in wei
   */
  async function getEthereumGasPrice() {
    const provider = getEthereumProvider();
    if (!provider) throw new Error('NO_PROVIDER');

    const gasPriceHex = await provider.request({ method: 'eth_gasPrice' });
    return BigInt(gasPriceHex).toString();
  }

  /**
   * Sign a message with Ethereum wallet
   * @param {string} address - Signer address
   * @param {string} message - Message to sign
   * @returns {Promise<string>} Signature
   */
  async function signEthereumMessage(address, message) {
    const provider = getEthereumProvider();
    if (!provider) throw new Error('NO_PROVIDER');

    try {
      const signature = await provider.request({
        method: 'personal_sign',
        params: [message, address],
      });
      return signature;
    } catch (error) {
      if (error.code === 4001) {
        throw new Error('USER_REJECTED');
      }
      throw error;
    }
  }

  /**
   * Get ethers.js BrowserProvider for advanced operations
   * @returns {Object} ethers BrowserProvider
   */
  function getEthersProvider() {
    const provider = getEthereumProvider();
    if (!provider) throw new Error('NO_PROVIDER');
    if (typeof ethers === 'undefined') throw new Error('ETHERS_NOT_LOADED');

    return new ethers.BrowserProvider(provider);
  }

  /**
   * Get ethers.js signer for signing transactions
   * @returns {Promise<Object>} ethers Signer
   */
  async function getEthersSigner() {
    const provider = getEthersProvider();
    return await provider.getSigner();
  }

  /**
   * Register event listeners for account/chain changes
   * @param {Function} onAccountsChanged - Callback for account changes
   * @param {Function} onChainChanged - Callback for chain changes
   * @param {Function} onDisconnect - Callback for disconnect
   */
  function registerEthereumListeners(onAccountsChanged, onChainChanged, onDisconnect) {
    const provider = getEthereumProvider();
    if (!provider) return;

    if (onAccountsChanged) {
      provider.on('accountsChanged', onAccountsChanged);
    }
    if (onChainChanged) {
      provider.on('chainChanged', (chainIdHex) => {
        onChainChanged(parseInt(chainIdHex, 16));
      });
    }
    if (onDisconnect) {
      provider.on('disconnect', onDisconnect);
    }
  }

  /**
   * Remove Ethereum event listeners
   */
  function removeEthereumListeners() {
    const provider = getEthereumProvider();
    if (!provider) return;

    provider.removeAllListeners('accountsChanged');
    provider.removeAllListeners('chainChanged');
    provider.removeAllListeners('disconnect');
  }

  // Helper to detect provider type
  function detectProviderType(provider) {
    if (provider.isMetaMask && !provider.isCoinbaseWallet) return 'metamask';
    if (provider.isCoinbaseWallet) return 'coinbase';
    if (provider.isRainbow) return 'rainbow';
    if (provider.isTrust) return 'trust';
    if (provider.isBraveWallet) return 'brave';
    return 'generic';
  }

  // ============================================
  // Solana Wallet Detection & Connection
  // ============================================

  /**
   * Detect available Solana wallet providers
   * @returns {Object} Object with detected providers
   */
  function detectSolanaProviders() {
    const providers = {
      hasAnyProvider: false,
      phantom: false,
      solflare: false,
    };

    // Check for Phantom
    if (window.solana && window.solana.isPhantom) {
      providers.hasAnyProvider = true;
      providers.phantom = true;
    }

    // Check for Solflare
    if (window.solflare && window.solflare.isSolflare) {
      providers.hasAnyProvider = true;
      providers.solflare = true;
    }

    return providers;
  }

  /**
   * Wrap a Solana provider in a mutable plain object.
   * Browser extensions seal/freeze window.solana and window.solflare,
   * and may define properties as non-writable. The Turbo SDK needs to
   * reassign signMessage on the adapter, which fails on sealed objects.
   * This creates a plain mutable wrapper that delegates to the real provider.
   * @param {Object} provider - The raw Solana provider (window.solana etc.)
   * @returns {Object} A mutable wrapper
   */
  function wrapSolanaProvider(provider) {
    if (!provider) return null;
    return {
      publicKey: provider.publicKey,
      signMessage: provider.signMessage.bind(provider),
      signTransaction: provider.signTransaction.bind(provider),
      signAllTransactions: provider.signAllTransactions
        ? provider.signAllTransactions.bind(provider)
        : undefined,
      signAndSendTransaction: provider.signAndSendTransaction
        ? provider.signAndSendTransaction.bind(provider)
        : undefined,
      connect: provider.connect ? provider.connect.bind(provider) : undefined,
      disconnect: provider.disconnect
        ? provider.disconnect.bind(provider)
        : undefined,
      connected: provider.connected,
      isPhantom: provider.isPhantom,
      isSolflare: provider.isSolflare,
    };
  }

  /**
   * Get Solana provider
   * @param {string} preferred - 'phantom' or 'solflare'
   * @returns {Object|null} The provider or null
   */
  function getSolanaProvider(preferred) {
    if (preferred === 'solflare' && window.solflare && window.solflare.isSolflare) {
      return window.solflare;
    }
    if (preferred === 'phantom' && window.solana && window.solana.isPhantom) {
      return window.solana;
    }
    // Default to Phantom if available
    if (window.solana && window.solana.isPhantom) {
      return window.solana;
    }
    if (window.solflare && window.solflare.isSolflare) {
      return window.solflare;
    }
    return null;
  }

  /**
   * Connect to a Solana wallet
   * @param {string} providerPreference - 'phantom' or 'solflare'
   * @returns {Promise<Object>} Connection result with publicKey
   */
  async function connectSolanaWallet(providerPreference) {
    const provider = getSolanaProvider(providerPreference);

    if (!provider) {
      throw new Error('NO_PROVIDER');
    }

    try {
      // Disconnect first to clear any stale provider state
      // (Phantom's service worker can break after disconnect/reconnect cycles)
      if (provider.disconnect) {
        try { await provider.disconnect(); } catch (_) {}
      }

      const response = await provider.connect();
      // Some wallets return { publicKey } in the response,
      // others set it on the provider object directly
      const pk = response?.publicKey || provider.publicKey;
      if (!pk) {
        throw new Error('NO_PUBLIC_KEY');
      }
      const publicKey = pk.toString();

      return {
        address: publicKey,
        providerType: provider.isPhantom ? 'phantom' : 'solflare',
      };
    } catch (error) {
      if (error.code === 4001 || error.message?.includes('rejected')) {
        throw new Error('USER_REJECTED');
      }
      throw error;
    }
  }

  /**
   * Disconnect Solana wallet
   * @param {string} providerPreference - 'phantom' or 'solflare'
   */
  async function disconnectSolanaWallet(providerPreference) {
    const provider = getSolanaProvider(providerPreference);
    if (provider && provider.disconnect) {
      await provider.disconnect();
    }
  }

  /**
   * Check if Solana wallet is connected
   * @param {string} providerPreference - 'phantom' or 'solflare'
   * @returns {boolean}
   */
  function isSolanaConnected(providerPreference) {
    const provider = getSolanaProvider(providerPreference);
    return provider ? provider.isConnected : false;
  }

  /**
   * Get connected Solana public key
   * @param {string} providerPreference - 'phantom' or 'solflare'
   * @returns {string|null}
   */
  function getSolanaPublicKey(providerPreference) {
    const provider = getSolanaProvider(providerPreference);
    if (provider && provider.publicKey) {
      return provider.publicKey.toString();
    }
    return null;
  }

  /**
   * Sign a message with Solana wallet
   * @param {string} providerPreference - 'phantom' or 'solflare'
   * @param {string} message - Message to sign
   * @returns {Promise<Uint8Array>} 64-byte Ed25519 signature
   */
  async function signSolanaMessage(providerPreference, message) {
    const provider = getSolanaProvider(providerPreference);
    if (!provider) throw new Error('NO_PROVIDER');

    const encodedMessage = new TextEncoder().encode(message);
    try {
      const result = await provider.signMessage(encodedMessage, 'utf8');
      // Phantom returns { signature: Uint8Array, publicKey: PublicKey }
      // Solflare may return Uint8Array directly or { signature: Uint8Array }
      const signature = result.signature || result;
      return new Uint8Array(signature);
    } catch (error) {
      if (error.code === 4001 || error.message?.includes('rejected')) {
        throw new Error('USER_REJECTED');
      }
      throw error;
    }
  }

  /**
   * Register Solana event listeners
   * @param {string} providerPreference - 'phantom' or 'solflare'
   * @param {Function} onConnect - Callback for connect
   * @param {Function} onDisconnect - Callback for disconnect
   * @param {Function} onAccountChange - Callback for account change
   */
  function registerSolanaListeners(providerPreference, onConnect, onDisconnect, onAccountChange) {
    const provider = getSolanaProvider(providerPreference);
    if (!provider) return;

    if (onConnect) {
      provider.on('connect', onConnect);
    }
    if (onDisconnect) {
      provider.on('disconnect', onDisconnect);
    }
    if (onAccountChange) {
      provider.on('accountChanged', (publicKey) => {
        if (publicKey) {
          onAccountChange(publicKey.toString());
        } else {
          onAccountChange(null);
        }
      });
    }
  }

  /**
   * Remove Solana event listeners
   * @param {string} providerPreference - 'phantom' or 'solflare'
   */
  function removeSolanaListeners(providerPreference) {
    const provider = getSolanaProvider(providerPreference);
    if (!provider) return;

    if (provider.removeAllListeners) {
      provider.removeAllListeners('connect');
      provider.removeAllListeners('disconnect');
      provider.removeAllListeners('accountChanged');
    }
  }

  // ============================================
  // Expose API to window object
  // ============================================

  window.CryptoWalletBridge = {
    // Ethereum
    detectEthereumProviders,
    getEthereumProvider,
    connectEthereumWallet,
    getEthereumAccounts,
    getEthereumChainId,
    switchEthereumChain,
    addEthereumChain,
    getEthereumBalance,
    estimateEthereumGas,
    getEthereumGasPrice,
    signEthereumMessage,
    getEthersProvider,
    getEthersSigner,
    registerEthereumListeners,
    removeEthereumListeners,

    // Solana
    detectSolanaProviders,
    getSolanaProvider,
    wrapSolanaProvider,
    connectSolanaWallet,
    disconnectSolanaWallet,
    isSolanaConnected,
    getSolanaPublicKey,
    signSolanaMessage,
    registerSolanaListeners,
    removeSolanaListeners,
  };

  console.log('Crypto Wallet Bridge initialized');
})();
