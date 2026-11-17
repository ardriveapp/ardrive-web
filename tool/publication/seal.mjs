// Private drive and folder pages, publication.json version 3
// (docs/ArweaveFS.md, "Private publications"): the publication key, its
// slots, and the sealed block that holds the page's file keys.
//
// Pure functions on node:crypto alone, no packages, no network. This is the
// reference the app's Dart code, the phase 2 app loader and core-js are held
// to through the vectors vectors.mjs writes. Every output is deterministic
// for fixed inputs: randomness (keys, salts, IVs) is always passed in.

import crypto from 'node:crypto';

/** The publication.json version of a private drive or folder page. */
export const PRIVATE_PUBLICATION_VERSION = 3;

/** The version of the sealed block's JSON, inside the encryption. */
export const SEALED_VERSION = 1;

export const CIPHER = 'AES256-GCM';

/** What a writer uses until the speed test says otherwise. */
export const ARGON2_DEFAULTS = Object.freeze({ m: 65536, t: 3, p: 1 });

/**
 * A reader never runs a password slot outside these bounds: a page could
 * otherwise ask a visitor's browser for gigabytes. m is in KiB.
 */
export const ARGON2_BOUNDS = Object.freeze({
  m: [8192, 262144],
  t: [1, 10],
  p: [1, 4],
  saltBytes: 16,
});

const KEY_BYTES = 32;
const IV_BYTES = 12;
const TAG_BYTES = 16;

const SLOT_AAD = 'ArDrive publication slot v1|';
const SEALED_AAD = 'ArDrive publication sealed v1|';
const OWNER_INFO = 'ArDrive publication owner v1|';

// base64url without padding, as ArFS writes keys and IVs.
export const b64u = (bytes) => Buffer.from(bytes).toString('base64url');

export function fromB64u(text, { bytes, what }) {
  if (typeof text !== 'string' || !/^[A-Za-z0-9_-]*$/.test(text)) {
    throw new SealError('invalid', `${what} is not base64url`);
  }
  const out = Buffer.from(text, 'base64url');
  if (bytes != null && out.length !== bytes) {
    throw new SealError('invalid', `${what} must be ${bytes} bytes`);
  }
  // Rejects non-canonical encodings, so one value has one spelling.
  if (b64u(out) !== text) throw new SealError('invalid', `${what} is not canonical base64url`);
  return out;
}

export class SealError extends Error {
  /** @param {'invalid'|'no-match'|'out-of-bounds'} code */
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

/** Sorted keys at every depth, no whitespace: one byte string per value. */
export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    const keys = Object.keys(value).sort();
    return `{${keys.map((k) => `${JSON.stringify(k)}:${canonicalJson(value[k])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function gcmEncrypt(key, iv, plaintext, aad) {
  const c = crypto.createCipheriv('aes-256-gcm', key, iv);
  c.setAAD(Buffer.from(aad, 'utf8'));
  return Buffer.concat([c.update(plaintext), c.final(), c.getAuthTag()]);
}

function gcmDecrypt(key, iv, sealed, aad) {
  if (sealed.length < TAG_BYTES) throw new SealError('no-match', 'ciphertext is too short');
  const d = crypto.createDecipheriv('aes-256-gcm', key, iv);
  d.setAAD(Buffer.from(aad, 'utf8'));
  d.setAuthTag(sealed.subarray(sealed.length - TAG_BYTES));
  try {
    return Buffer.concat([d.update(sealed.subarray(0, sealed.length - TAG_BYTES)), d.final()]);
  } catch {
    throw new SealError('no-match', 'the key does not open this');
  }
}

/** The password, NFC-normalised, as UTF-8: "é" typed either way is one password. */
export const passwordBytes = (password) => Buffer.from(password.normalize('NFC'), 'utf8');

export function checkArgon2Params({ m, t, p }) {
  for (const [name, value] of Object.entries({ m, t, p })) {
    const [lo, hi] = ARGON2_BOUNDS[name];
    if (!Number.isInteger(value) || value < lo || value > hi) {
      throw new SealError('out-of-bounds', `argon2id ${name}=${value} is outside ${lo}..${hi}`);
    }
  }
}

/** Argon2id (RFC 9106, version 0x13), 32-byte output, no secret, no associated data. */
export function passwordKek(password, { salt, m, t, p }) {
  checkArgon2Params({ m, t, p });
  return crypto.argon2Sync('argon2id', {
    message: passwordBytes(password),
    nonce: salt,
    parallelism: p,
    tagLength: KEY_BYTES,
    memory: m,
    passes: t,
  });
}

/**
 * HKDF-SHA256 (RFC 5869) over the drive key, empty salt. A key made for this
 * one publication: the drive key itself is never used to wrap anything.
 */
export function ownerKek(driveKey, publicationId) {
  return Buffer.from(
    crypto.hkdfSync('sha256', driveKey, Buffer.alloc(0), Buffer.from(OWNER_INFO + publicationId, 'utf8'), KEY_BYTES),
  );
}

/** AES-256-GCM of the publication key, bound to the publication by its associated data. */
export const wrapKey = (kek, iv, publicationKey, publicationId) =>
  gcmEncrypt(kek, iv, publicationKey, SLOT_AAD + publicationId);

export function unwrapKey(kek, iv, wrapped, publicationId) {
  const key = gcmDecrypt(kek, iv, wrapped, SLOT_AAD + publicationId);
  if (key.length !== KEY_BYTES) throw new SealError('invalid', 'a wrapped key must be 32 bytes');
  return key;
}

export function passwordSlot({ password, salt, iv, m, t, p, publicationKey, publicationId }) {
  const kek = passwordKek(password, { salt, m, t, p });
  return {
    type: 'password',
    kdf: 'argon2id',
    salt: b64u(salt),
    m,
    t,
    p,
    cipher: CIPHER,
    iv: b64u(iv),
    wrapped: b64u(wrapKey(kek, iv, publicationKey, publicationId)),
  };
}

export function ownerSlot({ driveKey, iv, publicationKey, publicationId }) {
  return {
    type: 'owner',
    kdf: 'hkdf-sha256',
    cipher: CIPHER,
    iv: b64u(iv),
    wrapped: b64u(wrapKey(ownerKek(driveKey, publicationId), iv, publicationKey, publicationId)),
  };
}

/** The sealed block's bytes: canonical JSON under the publication key. */
export const sealBlock = (publicationKey, iv, block, publicationId) =>
  gcmEncrypt(publicationKey, iv, Buffer.from(canonicalJson(block), 'utf8'), SEALED_AAD + publicationId);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const TX_ID = /^[A-Za-z0-9_-]{43}$/;
// Letters, digits, '.', '_', '-' and '/'; no leading '/', no empty, '.' or '..' segment.
const isPlainPath = (path) =>
  typeof path === 'string' &&
  /^[A-Za-z0-9._\/-]+$/.test(path) &&
  path.split('/').every((segment) => segment !== '' && segment !== '.' && segment !== '..');

const isObject = (v) => v != null && typeof v === 'object' && !Array.isArray(v);

function need(cond, message) {
  if (!cond) throw new SealError('invalid', message);
}

/**
 * publication.json for a private drive or folder page. Nothing in it is
 * secret: no names, no file count, no keys except wrapped ones.
 */
export function buildPrivatePublicationJson({
  publicationId,
  driveId,
  folderId,
  owner,
  sealed,
  slots,
  title = '',
  description,
  ownerName,
  keywords,
  license,
  images,
  publishedAt,
  names,
  viewer,
}) {
  const config = {
    version: PRIVATE_PUBLICATION_VERSION,
    publicationId,
    driveId,
    scope: folderId ? { type: 'folder', folderId } : { type: 'drive' },
    privacy: 'private',
    owner,
    ...(ownerName ? { ownerName } : {}),
    sealed: { path: 'sealed', txId: sealed.txId, cipher: CIPHER, iv: sealed.iv },
    slots,
    title,
    ...(description ? { description } : {}),
  };
  if (keywords?.length) config.keywords = keywords;
  if (license) config.license = license;
  if (images && Object.keys(images).length) config.images = images;
  if (publishedAt) config.publishedAt = publishedAt;
  if (names?.length) config.names = names;
  if (viewer) config.viewer = { release: viewer.release, manifest: viewer.manifest };
  return `${JSON.stringify(config, null, 2)}\n`;
}

/**
 * The reader's checks on a version 3 publication.json, beyond JSON parsing.
 * Returns the usable slots: unknown slot types are ignored, and a password
 * slot outside the bounds is never run.
 */
export function readPrivatePublication(config) {
  need(isObject(config), 'publication.json must be an object');
  need(config.version === PRIVATE_PUBLICATION_VERSION, 'version must be 3');
  need(config.privacy === 'private', 'a version 3 page is private');
  need(typeof config.publicationId === 'string' && UUID.test(config.publicationId), 'publicationId must be a lowercase UUID');
  need(typeof config.driveId === 'string' && UUID.test(config.driveId), 'driveId must be a lowercase UUID');
  need(isObject(config.scope), 'scope must be an object');
  if (config.scope.type === 'folder') {
    need(UUID.test(config.scope.folderId ?? ''), 'scope.folderId must be a lowercase UUID');
  } else {
    need(config.scope.type === 'drive', 'scope.type must be drive or folder');
  }
  need(typeof config.owner === 'string' && TX_ID.test(config.owner), 'owner must be an Arweave address');
  need(typeof config.title === 'string', 'title must be a string, and may be empty');
  need(config.snapshot === undefined && config.file === undefined && config.fileCount === undefined,
    'a private page has no snapshot, file or fileCount');

  const s = config.sealed;
  need(isObject(s), 'sealed must be an object');
  need(isPlainPath(s.path), 'sealed.path must be a plain relative path');
  need(typeof s.txId === 'string' && TX_ID.test(s.txId), 'sealed.txId must be a transaction ID');
  need(s.cipher === CIPHER, `sealed.cipher must be ${CIPHER}`);
  const sealedIv = fromB64u(s.iv, { bytes: IV_BYTES, what: 'sealed.iv' });

  need(Array.isArray(config.slots), 'slots must be an array');
  const passwordSlots = [];
  const ownerSlots = [];
  for (const slot of config.slots) {
    if (!isObject(slot)) continue;
    if (slot.type === 'password' && slot.kdf === 'argon2id' && slot.cipher === CIPHER) {
      try {
        checkArgon2Params(slot);
        const salt = fromB64u(slot.salt, { what: 'slot salt' });
        if (salt.length < ARGON2_BOUNDS.saltBytes) throw new SealError('out-of-bounds', 'a slot salt is at least 16 bytes');
        passwordSlots.push({
          salt,
          m: slot.m,
          t: slot.t,
          p: slot.p,
          iv: fromB64u(slot.iv, { bytes: IV_BYTES, what: 'slot iv' }),
          wrapped: fromB64u(slot.wrapped, { bytes: KEY_BYTES + TAG_BYTES, what: 'slot wrapped' }),
        });
      } catch (e) {
        if (!(e instanceof SealError)) throw e;
        // Skipped, not fatal: the link key may still open the page.
      }
    } else if (slot.type === 'owner' && slot.kdf === 'hkdf-sha256' && slot.cipher === CIPHER) {
      ownerSlots.push({
        iv: fromB64u(slot.iv, { bytes: IV_BYTES, what: 'slot iv' }),
        wrapped: fromB64u(slot.wrapped, { bytes: KEY_BYTES + TAG_BYTES, what: 'slot wrapped' }),
      });
    }
  }
  return { sealedIv, passwordSlots, ownerSlots };
}

/** The checks on the decrypted sealed block. It must describe the page it came with. */
export function readSealedBlock(block, config) {
  need(isObject(block), 'the sealed block must be an object');
  need(block.v === SEALED_VERSION, 'sealed v must be 1');
  need(isObject(block.scope) && block.scope.type === config.scope.type &&
    (block.scope.type !== 'folder' || block.scope.folderId === config.scope.folderId),
    "the sealed scope must be the page's scope");
  need(UUID.test(block.rootFolderId ?? ''), 'rootFolderId must be a lowercase UUID');

  const c = block.catalog;
  need(isObject(c), 'catalog must be an object');
  need(isPlainPath(c.path), 'catalog.path must be a plain relative path');
  need(typeof c.txId === 'string' && TX_ID.test(c.txId), 'catalog.txId must be a transaction ID');
  fromB64u(c.key, { bytes: KEY_BYTES, what: 'catalog.key' });
  need(isObject(c.tags) && Object.values(c.tags).every((v) => typeof v === 'string'), 'catalog.tags values are strings');
  need(c.tags.Cipher === CIPHER && typeof c.tags['Cipher-IV'] === 'string', 'catalog.tags carry Cipher and Cipher-IV');

  need(Number.isInteger(block.fileCount) && block.fileCount >= 0, 'fileCount must be a non-negative integer');
  need(isObject(block.files), 'files must be an object');
  for (const [fileId, key] of Object.entries(block.files)) {
    need(UUID.test(fileId), 'a files key must be a lowercase UUID');
    fromB64u(key, { bytes: KEY_BYTES, what: `the key of ${fileId}` });
  }
  need(isObject(block.ciphers), 'ciphers must be an object');
  for (const [txId, entry] of Object.entries(block.ciphers)) {
    need(TX_ID.test(txId), 'a ciphers key must be a transaction ID');
    need(isObject(entry) && typeof entry.cipher === 'string' && typeof entry.iv === 'string',
      `ciphers.${txId} needs cipher and iv`);
  }
  return block;
}

/** Whether typed text could be a pasted publication key: 43 base64url characters. */
export const looksLikeKey = (text) => /^[A-Za-z0-9_-]{43}$/.test(text);

function tryKey(key, config, sealedBytes, sealedIv) {
  const plain = gcmDecrypt(key, sealedIv, sealedBytes, SEALED_AAD + config.publicationId);
  let block;
  try {
    block = JSON.parse(plain.toString('utf8'));
  } catch {
    throw new SealError('invalid', 'the sealed block is not JSON');
  }
  return { publicationKey: key, block: readSealedBlock(block, config) };
}

/**
 * Opens a page. `linkKey` is the `k` in the link; `input` is what a visitor
 * typed (a pasted key or a password); `driveKey` is the owner's. Tried in
 * that order. Throws SealError 'no-match' when nothing opens it.
 */
export function openPage({ config, sealedBytes, linkKey, input, driveKey }) {
  const { sealedIv, passwordSlots, ownerSlots } = readPrivatePublication(config);
  const attempt = (key) => {
    try {
      return tryKey(key, config, sealedBytes, sealedIv);
    } catch (e) {
      if (e instanceof SealError && e.code === 'no-match') return null;
      throw e;
    }
  };

  if (linkKey != null) {
    const opened = looksLikeKey(linkKey) && attempt(fromB64u(linkKey, { bytes: KEY_BYTES, what: 'the link key' }));
    if (opened) return { ...opened, via: 'link' };
  }
  if (input != null) {
    if (looksLikeKey(input)) {
      const opened = attempt(fromB64u(input, { bytes: KEY_BYTES, what: 'the typed key' }));
      if (opened) return { ...opened, via: 'key' };
    }
    for (const slot of passwordSlots) {
      let key;
      try {
        key = unwrapKey(passwordKek(input, slot), slot.iv, slot.wrapped, config.publicationId);
      } catch (e) {
        if (e instanceof SealError && e.code === 'no-match') continue;
        throw e;
      }
      const opened = attempt(key);
      if (opened) return { ...opened, via: 'password' };
    }
  }
  if (driveKey != null) {
    const kek = ownerKek(driveKey, config.publicationId);
    for (const slot of ownerSlots) {
      let key;
      try {
        key = unwrapKey(kek, slot.iv, slot.wrapped, config.publicationId);
      } catch (e) {
        if (e instanceof SealError && e.code === 'no-match') continue;
        throw e;
      }
      const opened = attempt(key);
      if (opened) return { ...opened, via: 'owner' };
    }
  }
  throw new SealError('no-match', 'nothing given opens this page');
}
