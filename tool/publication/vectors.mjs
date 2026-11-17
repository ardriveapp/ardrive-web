// The test vectors for private drive and folder pages (seal.mjs): fixed
// inputs, and what the reference makes of them. The Dart code, the phase 2
// app loader and core-js are each held to this file.
//
//   node tool/publication/vectors.mjs          # rewrites the vectors
//   node --test tool/publication/seal.test.mjs # checks they are current
//
// Every key, salt and IV here is a fixed value (`fixed` below) so the file
// is the same on every run. They are test values: never reuse one.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ARGON2_DEFAULTS,
  CIPHER,
  b64u,
  buildPrivatePublicationJson,
  canonicalJson,
  ownerKek,
  ownerSlot,
  passwordKek,
  passwordSlot,
  sealBlock,
  wrapKey,
} from './seal.mjs';

export const VECTORS_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../test/publication/fixtures/sealed/vectors.json',
);

/** n bytes (at most 32) named by a label: SHA-256 of "ardrive-vector|<label>". */
const fixed = (label, n = 32) =>
  crypto.createHash('sha256').update(`ardrive-vector|${label}`).digest().subarray(0, n);

const hex = (bytes) => Buffer.from(bytes).toString('hex');

/** The fastest settings a reader accepts, so page vectors open quickly in tests. */
const FAST = { m: 8192, t: 1, p: 1 };

const txIdOf = (label) => b64u(fixed(`tx|${label}`));
const OWNER = txIdOf('owner address');
const DRIVE_ID = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const ROOT_FOLDER_ID = '5a1e8d0c-1b6f-4f43-9a63-0c6a4b6f2e11';
const FOLDER_ID = '9d2f4c3a-7e85-4b1e-8f0a-3c5d6e7f8a9b';
const FILE_A = '2b7c9e1d-4f3a-4c8b-9e2d-1a0b3c4d5e6f';
const FILE_B = 'e4f5a6b7-c8d9-4e0f-a1b2-c3d4e5f60718';
const txId = txIdOf;

function argon2Vectors() {
  const cases = [
    { name: 'ascii, fastest accepted settings', password: 'correct horse battery staple', ...FAST },
    { name: 'two lanes', password: 'correct horse battery staple', m: 8192, t: 2, p: 2 },
    { name: 'writer defaults', password: 'correct horse battery staple', ...ARGON2_DEFAULTS },
    // The same password typed composed and decomposed: NFC makes them one.
    { name: 'NFC, composed', password: 'Crème brûlée', ...FAST },
    { name: 'NFC, decomposed', password: 'Crème brûlée', ...FAST },
    { name: 'empty password', password: '', ...FAST },
  ];
  return cases.map(({ name, password, m, t, p }) => {
    const salt = fixed(`salt|${name}`, 16);
    return {
      name,
      password,
      passwordUtf8Hex: hex(Buffer.from(password, 'utf8')),
      salt: b64u(salt),
      m,
      t,
      p,
      kek: hex(passwordKek(password, { salt, m, t, p })),
    };
  });
}

/** RFC 9106 section 5.3, so an implementation can be checked apart from this scheme. */
const RFC9106_ARGON2ID = {
  password: hex(Buffer.alloc(32, 0x01)),
  salt: hex(Buffer.alloc(16, 0x02)),
  secret: hex(Buffer.alloc(8, 0x03)),
  associatedData: hex(Buffer.alloc(12, 0x04)),
  m: 32,
  t: 3,
  p: 4,
  tagLength: 32,
  tag: '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
};

function sealedBlockFor({ folderId, label }) {
  return {
    v: 1,
    scope: folderId ? { type: 'folder', folderId } : { type: 'drive' },
    rootFolderId: ROOT_FOLDER_ID,
    catalog: {
      path: 'catalog',
      txId: txId(`${label}|catalog`),
      key: b64u(fixed(`${label}|catalog key`)),
      tags: {
        'App-Name': 'ArDrive-Web',
        'Block-End': '1879136',
        'Block-Start': '0',
        Cipher: CIPHER,
        'Cipher-IV': b64u(fixed(`${label}|catalog iv`, 12)),
        'Content-Type': 'application/octet-stream',
        'Drive-Id': DRIVE_ID,
        'Entity-Type': 'drive-state',
      },
    },
    files: {
      [FILE_A]: b64u(fixed(`${label}|file key A`)),
      [FILE_B]: b64u(fixed(`${label}|file key B`)),
    },
    ciphers: {
      [txId(`${label}|data A`)]: { cipher: 'AES256-GCM', iv: b64u(fixed(`${label}|data A iv`, 12)) },
      [txId(`${label}|data B`)]: { cipher: 'AES256-CTR', iv: b64u(fixed(`${label}|data B iv`, 16)) },
      [txId(`${label}|thumbnail A`)]: { cipher: 'AES256-GCM', iv: b64u(fixed(`${label}|thumbnail A iv`, 12)) },
    },
  };
}

function page({ label, folderId, password, title = '' }) {
  const publicationId = folderId ? '3f1e2d4c-5b6a-4798-8a9b-0c1d2e3f4a5b' : '7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d';
  const publicationKey = fixed(`${label}|publication key`);
  const driveKey = fixed(`${label}|drive key`);
  const block = sealedBlockFor({ folderId, label });
  const sealedIv = fixed(`${label}|sealed iv`, 12);
  const header = {
    publicationId,
    driveId: DRIVE_ID,
    owner: OWNER,
    scope: folderId ? { type: 'folder', folderId } : { type: 'drive' },
    title,
  };
  const sealedBytes = sealBlock(publicationKey, sealedIv, block, header);
  const slots = [];
  if (password != null) {
    slots.push(
      passwordSlot({
        password,
        salt: fixed(`${label}|password salt`, 16),
        iv: fixed(`${label}|password slot iv`, 12),
        ...FAST,
        publicationKey,
        publicationId,
      }),
    );
  }
  slots.push(ownerSlot({ driveKey, iv: fixed(`${label}|owner slot iv`, 12), publicationKey, publicationId }));
  const publicationJson = buildPrivatePublicationJson({
    publicationId,
    driveId: DRIVE_ID,
    folderId,
    owner: OWNER,
    sealed: { txId: txId(`${label}|sealed`), iv: b64u(sealedIv) },
    slots,
    title,
    publishedAt: '2026-11-17T12:00:00.000Z',
    viewer: { release: 'v3.1.0', manifest: txId('viewer') },
  });
  return {
    name: label,
    publicationJson,
    sealed: b64u(sealedBytes),
    sealedPlaintext: canonicalJson(block),
    linkKey: b64u(publicationKey),
    ...(password != null ? { password } : {}),
    driveKey: b64u(driveKey),
  };
}

/**
 * A password slot for a good page's key, made without the reader's bounds,
 * as a hostile or broken writer could. Settings start from the fastest ones.
 */
function unboundedSlot(good, { m = FAST.m, t = FAST.t, p = FAST.p, saltBytes = 16 }) {
  const config = JSON.parse(good.publicationJson);
  const label = `unbounded|${m}|${t}|${p}|${saltBytes}`;
  const salt = Buffer.concat([fixed(`${label}|salt`), fixed(`${label}|salt 2`), fixed(`${label}|salt 3`)]).subarray(0, saltBytes);
  const iv = fixed(`${label}|iv`, 12);
  const kek = crypto.argon2Sync('argon2id', {
    message: Buffer.from(good.password.normalize('NFC'), 'utf8'),
    nonce: salt, parallelism: p, tagLength: 32, memory: m, passes: t,
  });
  return {
    type: 'password', kdf: 'argon2id', salt: b64u(salt), m, t, p, cipher: CIPHER,
    iv: b64u(iv), wrapped: b64u(wrapKey(kek, iv, Buffer.from(good.linkKey, 'base64url'), config.publicationId)),
  };
}

/** The same bytes spelled with one of the unused low bits set. */
function looseSpelling(text) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  const loose = text.slice(0, -1) + alphabet[alphabet.indexOf(text.at(-1)) ^ 1];
  if (!Buffer.from(loose, 'base64url').equals(Buffer.from(text, 'base64url'))) throw new Error('no unused bits');
  return loose;
}

/** Pages a reader must refuse, each made from a good page by one change. */
function refusals(good) {
  const config = () => JSON.parse(good.publicationJson);
  const edit = (change) => {
    const c = config();
    change(c);
    return `${JSON.stringify(c, null, 2)}\n`;
  };
  const tampered = Buffer.from(good.sealed, 'base64url');
  tampered[0] ^= 0x01;

  // The same block for another folder, sealed under the same key: a page
  // must not open a block that describes something else.
  const otherScope = JSON.parse(good.sealedPlaintext);
  otherScope.scope.folderId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
  const resealed = sealBlock(
    Buffer.from(good.linkKey, 'base64url'),
    Buffer.from(config().sealed.iv, 'base64url'),
    otherScope,
    config(),
  );

  return [
    { name: 'wrong password', publicationJson: good.publicationJson, sealed: good.sealed,
      input: 'correct horse battery stapler', error: 'no-match' },
    { name: 'wrong link key', publicationJson: good.publicationJson, sealed: good.sealed,
      linkKey: b64u(fixed('not the key')), error: 'no-match' },
    { name: 'owner slot with another drive key', publicationJson: good.publicationJson, sealed: good.sealed,
      driveKey: b64u(fixed('another drive key')), error: 'no-match' },
    { name: 'one sealed byte changed', publicationJson: good.publicationJson, sealed: b64u(tampered),
      linkKey: good.linkKey, error: 'no-match' },
    { name: 'publicationId changed: slots and sealed are bound to it', sealed: good.sealed,
      publicationJson: edit((c) => { c.publicationId = '00000000-0000-4000-8000-000000000000'; }),
      linkKey: good.linkKey, input: good.password, error: 'no-match' },
    // Real slots that would open the page, made outside the bounds: a reader
    // must refuse to run them, not merely fail to open them.
    ...[
      ['passes above the bound', { t: 11 }],
      ['memory below the bound', { m: 4096 }],
      ['memory above the bound', { m: 262145 }],
      ['lanes above the bound', { m: 8192, p: 5 }],
      ['salt under 16 bytes', { saltBytes: 8 }],
      ['salt over 64 bytes', { saltBytes: 65 }],
    ].map(([what, params]) => ({
      name: `a password slot with ${what} is never run`, sealed: good.sealed, outOfBounds: true,
      publicationJson: edit((c) => { c.slots[0] = unboundedSlot(good, params); }), input: good.password, error: 'no-match',
    })),
    { name: 'a password slot with a non-canonical salt is never run', sealed: good.sealed, outOfBounds: true,
      publicationJson: edit((c) => { c.slots[0].salt = looseSpelling(c.slots[0].salt); }), input: good.password, error: 'no-match' },
    { name: 'only the first password slot is read', sealed: good.sealed,
      publicationJson: edit((c) => { c.slots = [unboundedSlot(good, { t: 11 }), c.slots[0], c.slots[1]]; }),
      input: good.password, error: 'no-match' },
    // The sealed part is bound to the page: reused under another drive,
    // owner or title, the right key no longer opens it.
    { name: 'driveId changed', sealed: good.sealed, linkKey: good.linkKey, error: 'no-match',
      publicationJson: edit((c) => { c.driveId = '00000000-0000-4000-8000-000000000000'; }) },
    { name: 'owner changed', sealed: good.sealed, linkKey: good.linkKey, error: 'no-match',
      publicationJson: edit((c) => { c.owner = txId('another owner'); }) },
    { name: 'title changed', sealed: good.sealed, linkKey: good.linkKey, error: 'no-match',
      publicationJson: edit((c) => { c.title = 'Tax records'; }) },
    { name: 'description added', sealed: good.sealed, linkKey: good.linkKey, error: 'no-match',
      publicationJson: edit((c) => { c.description = 'Tax records'; }) },
    { name: 'sealed block describes another folder', publicationJson: good.publicationJson, sealed: b64u(resealed),
      linkKey: good.linkKey, error: 'invalid' },
    { name: 'version 3 cannot be public', sealed: good.sealed,
      publicationJson: edit((c) => { c.privacy = 'public'; }), linkKey: good.linkKey, error: 'invalid' },
    { name: 'version 3 has no snapshot', sealed: good.sealed,
      publicationJson: edit((c) => { c.snapshot = { path: 'snapshot', txId: txId('snapshot'), tags: {} }; }),
      linkKey: good.linkKey, error: 'invalid' },
    { name: 'sealed iv is not 12 bytes', sealed: good.sealed,
      publicationJson: edit((c) => { c.sealed.iv = b64u(fixed('long iv', 16)); }), linkKey: good.linkKey, error: 'invalid' },
  ];
}

export function buildVectors() {
  const folderPage = page({ label: 'folder page with a password', folderId: FOLDER_ID, password: 'correct horse battery staple', title: 'Family photos' });
  const drivePage = page({ label: 'drive page, link only' });
  // Passwords of 43 base64url characters look like keys. Whether or not they
  // spell one, a reader tries them as a key, then against the slot.
  const keyShaped = (password, canonical) => {
    if (password.length !== 43) throw new Error('a key-shaped password is 43 characters');
    if ((b64u(Buffer.from(password, 'base64url')) === password) !== canonical) throw new Error(`canonical must be ${canonical}`);
    return page({ label: `drive page with a key-shaped password, ${canonical ? 'canonical' : 'not canonical'}`, password });
  };
  const keyShapedPages = [
    keyShaped('correct-horse-battery-staple-and-two-more-R', false),
    keyShaped('correct-horse-battery-staple-and-two-more-Q', true),
  ];

  const ownerCase = { driveKey: fixed('owner kek|drive key'), publicationId: '3f1e2d4c-5b6a-4798-8a9b-0c1d2e3f4a5b' };
  const wrapCase = {
    kek: fixed('wrap|kek'),
    iv: fixed('wrap|iv', 12),
    publicationKey: fixed('wrap|publication key'),
    publicationId: '3f1e2d4c-5b6a-4798-8a9b-0c1d2e3f4a5b',
  };

  return {
    about:
      'Private drive and folder pages (publication.json version 3). Written by tool/publication/vectors.mjs; ' +
      'see docs/ArweaveFS.md, "Private publications". Bytes are hex where named *Hex or kek/tag, else base64url without padding.',
    argon2id: argon2Vectors(),
    argon2idRfc9106: RFC9106_ARGON2ID,
    ownerKek: [{
      driveKey: b64u(ownerCase.driveKey),
      publicationId: ownerCase.publicationId,
      info: `ArDrive publication owner v1|${ownerCase.publicationId}`,
      kek: hex(ownerKek(ownerCase.driveKey, ownerCase.publicationId)),
    }],
    wrap: [{
      kek: hex(wrapCase.kek),
      iv: b64u(wrapCase.iv),
      publicationKey: b64u(wrapCase.publicationKey),
      publicationId: wrapCase.publicationId,
      aad: `ArDrive publication slot v1|${wrapCase.publicationId}`,
      wrapped: b64u(wrapKey(wrapCase.kek, wrapCase.iv, wrapCase.publicationKey, wrapCase.publicationId)),
    }],
    pages: [folderPage, drivePage, ...keyShapedPages],
    refusals: refusals(folderPage),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  fs.mkdirSync(path.dirname(VECTORS_PATH), { recursive: true });
  fs.writeFileSync(VECTORS_PATH, `${JSON.stringify(buildVectors(), null, 2)}\n`);
  console.log(`wrote ${path.relative(process.cwd(), VECTORS_PATH)}`);
}
