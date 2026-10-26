// Solana wallets through the Wallet Standard (Phantom, Solflare, Backpack,
// MetaMask's Solana account...). Used only as the ArNS wallet: it approves
// name changes. Signing in with Phantom and topping up with SOL stay in
// web/js/crypto_wallet_bridge.js.

import { getWallets } from '@wallet-standard/app';
import { Buffer } from 'buffer';

const CONNECT = 'standard:connect';
const DISCONNECT = 'standard:disconnect';
const EVENTS = 'standard:events';
const SIGN_MESSAGE = 'solana:signMessage';
const SIGN_TRANSACTION = 'solana:signTransaction';

// Called on load so wallets that inject before or after this script both
// register.
const wallets = getWallets();

let connected = null; // { wallet, account }
let offChange = null;
let accountListener = null;
let walletsListener = null;

function isSolanaWallet(wallet) {
  const features = wallet.features || {};
  return (
    CONNECT in features && SIGN_MESSAGE in features && SIGN_TRANSACTION in features
  );
}

function solanaWallets() {
  return wallets.get().filter(isSolanaWallet);
}

function notifyWallets() {
  if (walletsListener) walletsListener(listSolanaWallets());
}

wallets.on('register', notifyWallets);
wallets.on('unregister', notifyWallets);

function pickAccount(accounts) {
  if (!accounts || accounts.length === 0) return null;
  return (
    accounts.find((a) => (a.chains || []).some((c) => c.startsWith('solana:'))) ||
    accounts[0]
  );
}

function setConnected(wallet, account) {
  if (offChange) {
    offChange();
    offChange = null;
  }
  connected = account ? { wallet, account } : null;

  if (connected && EVENTS in wallet.features) {
    offChange = wallet.features[EVENTS].on('change', ({ accounts }) => {
      if (!accounts) return;
      const next = pickAccount(accounts);
      connected = next ? { wallet, account: next } : null;
      if (accountListener) accountListener(next ? next.address : '');
    });
  }
}

export function listSolanaWallets() {
  return JSON.stringify(
    solanaWallets().map((w) => ({ name: w.name, icon: w.icon })),
  );
}

/**
 * Connects the named wallet and returns the address, or '' when a silent
 * connect finds no authorised account.
 */
export async function connectSolanaWallet(name, silent) {
  const wallet = solanaWallets().find((w) => w.name === name);
  if (!wallet) throw new Error(`Solana wallet not found: ${name}`);

  const { accounts } = await wallet.features[CONNECT].connect({
    silent: !!silent,
  });
  const account = pickAccount(accounts);
  setConnected(wallet, account);
  return account ? account.address : '';
}

export async function disconnectSolanaWallet() {
  const wallet = connected && connected.wallet;
  setConnected(null, null);
  if (wallet && DISCONNECT in wallet.features) {
    await wallet.features[DISCONNECT].disconnect();
  }
  return true;
}

export function connectedSolanaAddress() {
  return connected ? connected.account.address : '';
}

export function connectedSolanaWalletName() {
  return connected ? connected.wallet.name : '';
}

/** One listener; called with the new address, or '' when none. */
export function setSolanaAccountListener(listener) {
  accountListener = listener || null;
}

/** One listener; called with the wallet list JSON when wallets come and go. */
export function setSolanaWalletsListener(listener) {
  walletsListener = listener || null;
}

function requireConnected() {
  if (!connected) throw new Error('No Solana wallet connected');
  return connected;
}

/**
 * Signs `data` (utf8 text, or base64 bytes when `encoding` is 'base64') and
 * returns the 64-byte ed25519 signature, base64.
 */
export async function solanaSignMessage(data, encoding) {
  const { wallet, account } = requireConnected();
  const message =
    encoding === 'base64'
      ? new Uint8Array(Buffer.from(data, 'base64'))
      : new TextEncoder().encode(data);
  const [output] = await wallet.features[SIGN_MESSAGE].signMessage({
    account,
    message,
  });
  return Buffer.from(output.signature).toString('base64');
}

/**
 * Signs a serialized transaction exactly as given and returns the signed
 * transaction, base64. Turbo has already signed these bytes as fee payer, so
 * they are never decoded and rebuilt here.
 */
export async function solanaSignTransaction(transactionBase64, chain) {
  const signed = await signTransactionBytes(
    new Uint8Array(Buffer.from(transactionBase64, 'base64')),
    chain,
  );
  return Buffer.from(signed).toString('base64');
}

export async function signTransactionBytes(bytes, chain) {
  const { wallet, account } = requireConnected();
  const [output] = await wallet.features[SIGN_TRANSACTION].signTransaction({
    account,
    transaction: bytes,
    ...(chain ? { chain } : {}),
  });
  return output.signedTransaction;
}

export function requireConnectedAddress() {
  return requireConnected().account.address;
}
