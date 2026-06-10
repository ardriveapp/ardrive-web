// Browser shim for Node.js 'crypto' module.
// Provides createHash and randomBytes using @noble/hashes (already a dep of @ar.io/sdk).

import { sha256 } from '@noble/hashes/sha256';

class Hash {
  constructor(algorithm) {
    if (algorithm !== 'sha256') {
      throw new Error(`Unsupported hash algorithm: ${algorithm}`);
    }
    this._chunks = [];
  }

  update(data) {
    if (typeof data === 'string') {
      data = new TextEncoder().encode(data);
    } else if (data instanceof ArrayBuffer) {
      data = new Uint8Array(data);
    }
    this._chunks.push(new Uint8Array(data));
    return this;
  }

  digest(encoding) {
    const totalLength = this._chunks.reduce((sum, c) => sum + c.length, 0);
    const merged = new Uint8Array(totalLength);
    let offset = 0;
    for (const chunk of this._chunks) {
      merged.set(chunk, offset);
      offset += chunk.length;
    }
    const hash = sha256(merged);

    if (encoding === 'hex') {
      return Array.from(hash).map(b => b.toString(16).padStart(2, '0')).join('');
    }
    if (encoding === 'base64') {
      return btoa(String.fromCharCode(...hash));
    }
    // Return as Buffer-like Uint8Array
    return hash;
  }
}

export function createHash(algorithm) {
  return new Hash(algorithm);
}

export function randomBytes(size) {
  const buf = new Uint8Array(size);
  globalThis.crypto.getRandomValues(buf);
  return buf;
}

export default { createHash, randomBytes };
