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
  m: [8192, 131072],
  t: [1, 6],
  p: [1, 4],
  saltBytes: [16, 64],
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
  // Not every Argon2id takes an empty message (hash-wasm, which the app
  // uses, doesn't), and an empty password protects nothing.
  if (passwordBytes(password).length === 0) throw new SealError('invalid', 'a password is at least one character');
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
  if (driveKey.length !== KEY_BYTES) throw new SealError('invalid', 'a drive key is 32 bytes');
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


const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const TX_ID = /^[A-Za-z0-9_-]{43}$/;
// A string test first: RegExp.test turns an array or number into text.
const isUuid = (v) => typeof v === 'string' && UUID.test(v);
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

/** A reader refuses a version 3 publication.json larger than this. */
export const MAX_PUBLICATION_JSON_BYTES = 65536;

/** A reader refuses a sealed part larger than this, before decrypting it. */
export const MAX_SEALED_BYTES = 32 * 1024 * 1024;

/** publication.json's text, size-checked and parsed. */
export function parsePublicationText(text) {
  need(Buffer.byteLength(text, 'utf8') <= MAX_PUBLICATION_JSON_BYTES, 'publication.json is too large');
  try {
    return JSON.parse(text);
  } catch {
    throw new SealError('invalid', 'publication.json is not JSON');
  }
}

/** The page's scope with only the keys the spec defines. */
const scopeOf = (scope) =>
  scope.type === 'folder' ? { type: 'folder', folderId: scope.folderId } : { type: 'drive' };

/**
 * What the sealed block is bound to, as its associated data: the page's
 * identity and the text everyone sees. A sealed part reused under another
 * drive, owner, scope, title or description does not open.
 */
export function sealedAad(config) {
  return SEALED_AAD + canonicalJson({
    description: config.description ?? '',
    driveId: config.driveId,
    owner: config.owner,
    publicationId: config.publicationId,
    scope: scopeOf(config.scope),
    title: config.title,
  });
}

/**
 * The sealed block's size is rounded up to a multiple of this, so the sealed
 * part's length does not give the file count away.
 */
export const SEALED_PAD_UNIT = 4096;

/**
 * [block] with a `pad` field: a string of ASCII spaces that brings the
 * canonical JSON's UTF-8 length up to the next multiple of SEALED_PAD_UNIT
 * (none when it already is one). A reader ignores `pad`, and a block
 * without one is valid.
 */
export function padSealedBlock(block) {
  const base = Buffer.byteLength(canonicalJson({ ...block, pad: '' }), 'utf8');
  const pad = ' '.repeat((SEALED_PAD_UNIT - (base % SEALED_PAD_UNIT)) % SEALED_PAD_UNIT);
  return { ...block, pad };
}

/** The sealed part's bytes: the block's canonical JSON, bound to its page. */
export const sealBlock = (publicationKey, iv, block, config) =>
  sealPlaintext(publicationKey, iv, Buffer.from(canonicalJson(block), 'utf8'), config);

/** Any plaintext sealed as a page's sealed part. Writers use sealBlock; tests use this for hostile blocks. */
export const sealPlaintext = (publicationKey, iv, plaintext, config) =>
  gcmEncrypt(publicationKey, iv, plaintext, sealedAad(config));

const PASSWORD_SLOT = (slot) => slot.type === 'password';
const OWNER_SLOT = (slot) => slot.type === 'owner';

/**
 * The reader's checks on a version 3 publication.json, beyond JSON parsing.
 * Only the first slot of each type is read; a password slot that is
 * malformed or outside the bounds is never run, and the page can still open
 * by key.
 */
export function readPrivatePublication(config) {
  need(isObject(config), 'publication.json must be an object');
  need(config.version === PRIVATE_PUBLICATION_VERSION, 'version must be 3');
  need(config.privacy === 'private', 'a version 3 page is private');
  need(isUuid(config.publicationId), 'publicationId must be a lowercase UUID');
  need(isUuid(config.driveId), 'driveId must be a lowercase UUID');
  need(isObject(config.scope), 'scope must be an object');
  if (config.scope.type === 'folder') {
    need(isUuid(config.scope.folderId), 'scope.folderId must be a lowercase UUID');
  } else {
    need(config.scope.type === 'drive', 'scope.type must be drive or folder');
  }
  need(typeof config.owner === 'string' && TX_ID.test(config.owner), 'owner must be an Arweave address');
  need(typeof config.title === 'string', 'title must be a string, and may be empty');
  need(config.description === undefined || typeof config.description === 'string', 'description must be a string');
  for (const key of ['rootFolderId', 'snapshot', 'file', 'fileCount']) {
    need(config[key] === undefined, `a private page has no ${key}`);
  }

  const s = config.sealed;
  need(isObject(s), 'sealed must be an object');
  need(isPlainPath(s.path), 'sealed.path must be a plain relative path');
  need(typeof s.txId === 'string' && TX_ID.test(s.txId), 'sealed.txId must be a transaction ID');
  need(s.cipher === CIPHER, `sealed.cipher must be ${CIPHER}`);
  const sealedIv = fromB64u(s.iv, { bytes: IV_BYTES, what: 'sealed.iv' });

  need(Array.isArray(config.slots), 'slots must be an array');
  const slots = config.slots.filter(isObject);

  let passwordSlot = null;
  const p = slots.find(PASSWORD_SLOT);
  if (p) {
    try {
      need(p.kdf === 'argon2id' && p.cipher === CIPHER, 'unknown password slot');
      checkArgon2Params(p);
      const salt = fromB64u(p.salt, { what: 'slot salt' });
      if (salt.length < ARGON2_BOUNDS.saltBytes[0] || salt.length > ARGON2_BOUNDS.saltBytes[1]) {
        throw new SealError('out-of-bounds', 'a slot salt is 16 to 64 bytes');
      }
      passwordSlot = {
        salt,
        m: p.m,
        t: p.t,
        p: p.p,
        iv: fromB64u(p.iv, { bytes: IV_BYTES, what: 'slot iv' }),
        wrapped: fromB64u(p.wrapped, { bytes: KEY_BYTES + TAG_BYTES, what: 'slot wrapped' }),
      };
    } catch (e) {
      if (!(e instanceof SealError)) throw e;
    }
  }

  let ownerSlot = null;
  const o = slots.find(OWNER_SLOT);
  if (o) {
    try {
      need(o.kdf === 'hkdf-sha256' && o.cipher === CIPHER, 'unknown owner slot');
      ownerSlot = {
        iv: fromB64u(o.iv, { bytes: IV_BYTES, what: 'slot iv' }),
        wrapped: fromB64u(o.wrapped, { bytes: KEY_BYTES + TAG_BYTES, what: 'slot wrapped' }),
      };
    } catch (e) {
      if (!(e instanceof SealError)) throw e;
    }
  }
  return { sealedIv, passwordSlot, ownerSlot };
}

/** The ciphers whose IV a reader checks; any other is ignored and looked up as usual. */
export const KNOWN_DATA_CIPHERS = Object.freeze(['AES256-GCM', 'AES256-CTR']);

/**
 * Whether two scopes name the same thing. Compared field by field, never by
 * serialising: a hostile block's folderId may be any JSON, nested deep
 * enough to overflow a recursive writer. Each must say its type: a missing
 * or unknown one is no scope at all.
 */
const sameScope = (a, b) => {
  const type = a.type;
  if ((type !== 'drive' && type !== 'folder') || type !== b.type) return false;
  return type === 'drive' || (isUuid(a.folderId) && a.folderId === b.folderId);
};

/** The checks on the decrypted sealed block. It must describe the page it came with. */
export function readSealedBlock(block, config) {
  need(isObject(block), 'the sealed block must be an object');
  need(block.v === SEALED_VERSION, 'sealed v must be 1');
  need(isObject(block.scope) && sameScope(block.scope, config.scope), "the sealed scope must be the page's scope");
  need(isUuid(block.rootFolderId), 'rootFolderId must be a lowercase UUID');

  const c = block.catalog;
  need(isObject(c), 'catalog must be an object');
  need(isPlainPath(c.path), 'catalog.path must be a plain relative path');
  need(typeof c.txId === 'string' && TX_ID.test(c.txId), 'catalog.txId must be a transaction ID');
  fromB64u(c.key, { bytes: KEY_BYTES, what: 'catalog.key' });
  need(isObject(c.tags) && Object.values(c.tags).every((v) => typeof v === 'string'), 'catalog.tags values are strings');
  need(c.tags.Cipher === CIPHER, 'catalog.tags.Cipher must be AES256-GCM');
  fromB64u(c.tags['Cipher-IV'], { bytes: IV_BYTES, what: 'catalog Cipher-IV' });

  need(isObject(block.files), 'files must be an object');
  for (const [fileId, key] of Object.entries(block.files)) {
    need(UUID.test(fileId), 'a files key must be a lowercase UUID');
    fromB64u(key, { bytes: KEY_BYTES, what: `the key of ${fileId}` });
  }
  need(isObject(block.ciphers), 'ciphers must be an object');
  for (const [txId, entry] of Object.entries(block.ciphers)) {
    need(TX_ID.test(txId), 'a ciphers key must be a transaction ID');
    need(isObject(entry) && typeof entry.cipher === 'string', `ciphers.${txId} needs a cipher`);
    if (KNOWN_DATA_CIPHERS.includes(entry.cipher)) {
      need(typeof entry.iv === 'string' && entry.iv.length > 0, `ciphers.${txId} needs an iv`);
      fromB64u(entry.iv, { what: `ciphers.${txId}.iv` });
    }
  }
  return block;
}

/** Whether typed text could be a pasted publication key: 43 base64url characters. */
export const looksLikeKey = (text) => /^[A-Za-z0-9_-]{43}$/.test(text);

/** The key typed text spells, or null: a non-canonical spelling is not a key, and may be a password. */
function keyFrom(text) {
  if (typeof text !== 'string' || !looksLikeKey(text)) return null;
  try {
    return fromB64u(text, { bytes: KEY_BYTES, what: 'a key' });
  } catch {
    return null;
  }
}

/**
 * Opens a page. `linkKey` is the `k` in the link; `input` is what a visitor
 * typed (a pasted key or a password); `driveKey` is the owner's. Tried in
 * that order: link key, typed key, password slot, owner slot. Throws
 * SealError 'no-match' when nothing opens it, and 'invalid' when a key
 * opens a block that breaks the rules.
 */
export function openPage({ config, sealedBytes, linkKey, input, driveKey }) {
  const { sealedIv, passwordSlot, ownerSlot } = readPrivatePublication(config);
  need(sealedBytes.length <= MAX_SEALED_BYTES, 'the sealed part is too large');
  const aad = sealedAad(config);

  const attempt = (key) => {
    let plain;
    try {
      plain = gcmDecrypt(key, sealedIv, sealedBytes, aad);
    } catch (e) {
      if (e instanceof SealError && e.code === 'no-match') return null;
      throw e;
    }
    let block;
    try {
      block = JSON.parse(plain.toString('utf8'));
    } catch {
      throw new SealError('invalid', 'the sealed block is not JSON');
    }
    return { publicationKey: key, block: readSealedBlock(block, config) };
  };
  const unwrapped = (kek, slot) => {
    try {
      return unwrapKey(kek, slot.iv, slot.wrapped, config.publicationId);
    } catch (e) {
      if (e instanceof SealError && e.code === 'no-match') return null;
      throw e;
    }
  };

  let kdfFailure = null;
  const fromLink = keyFrom(linkKey);
  if (fromLink) {
    const opened = attempt(fromLink);
    if (opened) return { ...opened, via: 'link' };
  }
  if (typeof input === 'string') {
    const typed = keyFrom(input);
    if (typed) {
      const opened = attempt(typed);
      if (opened) return { ...opened, via: 'key' };
    }
    if (passwordSlot && input.length > 0) {
      // Argon2id can fail without the password being wrong (no memory, no
      // module). The owner slot is still tried, and the failure is what is
      // thrown if nothing opens the page.
      let kek = null;
      try {
        kek = passwordKek(input, passwordSlot);
      } catch (e) {
        if (e instanceof SealError) throw e;
        kdfFailure = e;
      }
      const key = kek && unwrapped(kek, passwordSlot);
      const opened = key && attempt(key);
      if (opened) return { ...opened, via: 'password' };
    }
  }
  if (driveKey != null && ownerSlot) {
    const key = unwrapped(ownerKek(driveKey, config.publicationId), ownerSlot);
    const opened = key && attempt(key);
    if (opened) return { ...opened, via: 'owner' };
  }
  if (kdfFailure) throw kdfFailure;
  throw new SealError('no-match', 'nothing given opens this page');
}
