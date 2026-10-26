// A Solana test wallet for the e2e browser: a Wallet Standard wallet the page
// sees like Phantom, backed by throwaway keypairs that stay in this process.
// Used to test the ArNS wallet (docs/NAMES.md) on devnet. Never load a real
// wallet's key into it.
//
//   node solana_wallet.js new <file>     makes a keypair, writes it to <file>
//                                        (chmod 600) and prints its address
//   node solana_wallet.js address <file> prints a keypair file's address
//
// launch.js installs it when SOLANA_KEYS names keypair files (comma
// separated). The page gets a wallet called "E2E Test Wallet" whose account
// is the first key; its prompts are answered here, never by the page, so the
// secret keys never enter the browser. Each prompt is logged to net.log as a
// `solana` line.
//
// Switches, read on every prompt (files in E2E_DIR, no restart):
// - solana-account   a number: which SOLANA_KEYS entry is the account (the
//                    page notices within 3 s, as a wallet's account change)
// - solana-reject    reject prompts: `connect`, `message`, `transaction` or
//                    empty for all, as a user pressing Cancel would
// - solana-delay     milliseconds to wait before answering a transaction
//                    prompt, for a late signature
// In the page, localStorage `e2e-solana-hidden` = '1' before a reload hides
// the wallet, for the no-wallet state.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

function base58(bytes) {
  let n = BigInt('0x' + (Buffer.from(bytes).toString('hex') || '0'));
  let out = '';
  while (n > 0n) {
    out = ALPHABET[Number(n % 58n)] + out;
    n /= 58n;
  }
  for (const b of bytes) {
    if (b !== 0) break;
    out = '1' + out;
  }
  return out;
}

const b64url = (s) => Buffer.from(s, 'base64url');

// { d, x }: the ed25519 seed and public key, base64url, as in a JWK.
function newKeypair(file) {
  const { privateKey } = crypto.generateKeyPairSync('ed25519');
  const { d, x } = privateKey.export({ format: 'jwk' });
  fs.writeFileSync(file, JSON.stringify({ d, x }), { mode: 0o600 });
  fs.chmodSync(file, 0o600);
  return base58(b64url(x));
}

function loadKeypair(file) {
  const { d, x } = JSON.parse(fs.readFileSync(file, 'utf8'));
  return {
    address: base58(b64url(x)),
    publicKey: b64url(x),
    key: crypto.createPrivateKey({ key: { kty: 'OKP', crv: 'Ed25519', d, x }, format: 'jwk' }),
  };
}

function readCompactU16(bytes, offset) {
  let value = 0;
  for (let i = 0; i < 3; i++) {
    const b = bytes[offset + i];
    value |= (b & 0x7f) << (7 * i);
    if ((b & 0x80) === 0) return [value, offset + i + 1];
  }
  throw new Error('bad compact-u16');
}

// Signs a serialized transaction (legacy or v0) in the signer's slot, as a
// wallet does: the bytes are kept, only the signature is filled in.
function signTransaction(bytes, keypair) {
  const [count, sigStart] = readCompactU16(bytes, 0);
  const message = bytes.subarray(sigStart + 64 * count);
  let p = message[0] & 0x80 ? 1 : 0;
  const required = message[p];
  p += 3;
  const [keys, keysStart] = readCompactU16(message, p);
  let slot = -1;
  for (let i = 0; i < keys; i++) {
    if (keypair.publicKey.equals(message.subarray(keysStart + 32 * i, keysStart + 32 * i + 32))) slot = i;
  }
  if (slot < 0 || slot >= required || slot >= count) {
    throw new Error(`${keypair.address} is not a signer of this transaction`);
  }
  const out = Buffer.from(bytes);
  crypto.sign(null, message, keypair.key).copy(out, sigStart + 64 * slot);
  return out;
}

const WALLET_URL = 'https://e2e-solana.invalid/';

// Routes the page's wallet prompts to this process and registers the wallet
// in every page.
async function install(ctx, { keyFiles, e2eDir, log }) {
  const keypairs = keyFiles.map(loadKeypair);
  const control = (name) => {
    try { return fs.readFileSync(path.join(e2eDir, name), 'utf8').trim(); } catch (e) { return null; }
  };
  const current = () => keypairs[Math.min(Number(control('solana-account') || 0), keypairs.length - 1)];
  const rejects = (op) => {
    const r = control('solana-reject');
    return r !== null && (r === '' || r.split(/[\s,]+/).includes(op));
  };
  const cors = { 'access-control-allow-origin': '*', 'content-type': 'application/json' };
  const answer = (route, body) => route.fulfill({ status: 200, headers: cors, body: JSON.stringify(body) });

  await ctx.route(`${WALLET_URL}**`, async (route) => {
    const req = route.request();
    if (req.method() === 'OPTIONS') {
      return route.fulfill({ status: 204, headers: { ...cors, 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET, POST' } });
    }
    const op = new URL(req.url()).pathname.slice(1);
    const account = current();
    if (op === 'account') return answer(route, { address: account.address });
    const input = req.postDataJSON() || {};
    if (rejects(op === 'connect' ? 'connect' : op === 'signMessage' ? 'message' : 'transaction')) {
      log({ ev: 'solana', op, account: account.address, answer: 'rejected' });
      return answer(route, { rejected: true });
    }
    try {
      if (input.address && input.address !== account.address) throw new Error(`asked to sign as ${input.address}, the account is ${account.address}`);
      if (op === 'connect') {
        log({ ev: 'solana', op, account: account.address, answer: 'approved' });
        return answer(route, { address: account.address });
      }
      if (op === 'signMessage') {
        const message = Buffer.from(input.message, 'base64');
        log({ ev: 'solana', op, account: account.address, answer: 'approved', text: message.toString('utf8').replace(/\n/g, '|').slice(0, 200) });
        return answer(route, { signature: crypto.sign(null, message, account.key).toString('base64') });
      }
      if (op === 'signTransaction') {
        const delay = Number(control('solana-delay') || 0);
        if (delay > 0) await new Promise((r) => setTimeout(r, delay));
        const signed = signTransaction(Buffer.from(input.transaction, 'base64'), account);
        log({ ev: 'solana', op, account: account.address, answer: 'approved', delayMs: delay, bytes: signed.length });
        return answer(route, { signedTransaction: signed.toString('base64') });
      }
      return route.fulfill({ status: 404, headers: cors, body: '{}' });
    } catch (e) {
      log({ ev: 'solana', op, account: account.address, answer: 'error', err: String(e).slice(0, 200) });
      return answer(route, { error: String(e.message || e) });
    }
  });

  await ctx.addInitScript((url) => {
    if (localStorage.getItem('e2e-solana-hidden') === '1') return;
    const CHAINS = ['solana:mainnet', 'solana:devnet'];
    const AUTH = 'e2e-solana-authorized';
    const call = async (op, body) => {
      const res = await fetch(url + op, body ? { method: 'POST', headers: { 'content-type': 'text/plain' }, body: JSON.stringify(body) } : {});
      const out = await res.json();
      if (out.rejected) {
        const e = new Error('User rejected the request.');
        e.code = 4001;
        throw e;
      }
      if (out.error) throw new Error(out.error);
      return out;
    };
    const fromB58 = (s) => {
      const A = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
      let n = 0n;
      for (const c of s) n = n * 58n + BigInt(A.indexOf(c));
      const hex = n.toString(16).padStart(64, '0');
      return Uint8Array.from(hex.match(/../g).map((h) => parseInt(h, 16)));
    };
    const b64 = (bytes) => btoa(String.fromCharCode(...bytes));
    const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
    const toAccount = (address) => Object.freeze({
      address,
      publicKey: fromB58(address),
      chains: CHAINS,
      features: ['solana:signMessage', 'solana:signTransaction'],
    });
    const listeners = new Set();
    let accounts = [];
    const setAccounts = (next) => {
      accounts = next;
      listeners.forEach((l) => l({ accounts }));
    };
    // The account the launcher says is current; a change is reported to the
    // app as a wallet's account switch.
    setInterval(async () => {
      if (!accounts.length) return;
      try {
        const { address } = await call('account');
        if (address !== accounts[0].address) setAccounts([toAccount(address)]);
      } catch (e) {}
    }, 3000);
    const wallet = {
      version: '1.0.0',
      name: 'E2E Test Wallet',
      icon: 'data:image/svg+xml;base64,' + btoa('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="6" fill="#7a5af8"/><text x="16" y="22" font-size="14" text-anchor="middle" fill="#fff" font-family="sans-serif">E2E</text></svg>'),
      chains: CHAINS,
      get accounts() { return accounts; },
      features: {
        'standard:connect': {
          version: '1.0.0',
          connect: async ({ silent } = {}) => {
            if (silent && localStorage.getItem(AUTH) !== '1') return { accounts: [] };
            const { address } = await call('connect', {});
            localStorage.setItem(AUTH, '1');
            setAccounts([toAccount(address)]);
            return { accounts };
          },
        },
        'standard:disconnect': {
          version: '1.0.0',
          disconnect: async () => {
            localStorage.removeItem(AUTH);
            setAccounts([]);
          },
        },
        'standard:events': {
          version: '1.0.0',
          on: (event, listener) => {
            if (event !== 'change') return () => {};
            listeners.add(listener);
            return () => listeners.delete(listener);
          },
        },
        'solana:signMessage': {
          version: '1.0.0',
          signMessage: async (...inputs) => Promise.all(inputs.map(async ({ account, message }) => {
            const { signature } = await call('signMessage', { address: account.address, message: b64(message) });
            return { signedMessage: message, signature: unb64(signature) };
          })),
        },
        'solana:signTransaction': {
          version: '1.0.0',
          supportedTransactionVersions: ['legacy', 0],
          signTransaction: async (...inputs) => Promise.all(inputs.map(async ({ account, transaction }) => {
            const { signedTransaction } = await call('signTransaction', { address: account.address, transaction: b64(transaction) });
            return { signedTransaction: unb64(signedTransaction) };
          })),
        },
      },
    };
    const register = ({ register }) => register(wallet);
    try { window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register })); } catch (e) {}
    try { window.addEventListener('wallet-standard:app-ready', ({ detail }) => register(detail)); } catch (e) {}
  }, WALLET_URL);

  return keypairs.map((k) => k.address);
}

module.exports = { install, newKeypair, loadKeypair, signTransaction, base58 };

if (require.main === module) {
  const [cmd, file] = process.argv.slice(2);
  if (cmd === 'new' && file) {
    if (fs.existsSync(file)) {
      console.error(`${file} exists; not overwriting a key`);
      process.exit(1);
    }
    console.log(newKeypair(file));
  } else if (cmd === 'address' && file) {
    console.log(loadKeypair(file).address);
  } else {
    console.error('usage: node solana_wallet.js new <file> | address <file>');
    process.exit(2);
  }
}
