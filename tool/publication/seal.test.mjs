// node --test tool/publication/seal.test.mjs
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { test } from 'node:test';
import {
  SealError,
  canonicalJson,
  fromB64u,
  looksLikeKey,
  openPage,
  ownerKek,
  passwordKek,
  unwrapKey,
} from './seal.mjs';
import { VECTORS_PATH, buildVectors } from './vectors.mjs';

const vectors = JSON.parse(fs.readFileSync(VECTORS_PATH, 'utf8'));
const bytes = (text) => Buffer.from(text, 'base64url');

test('the vectors file is current', () => {
  assert.deepEqual(vectors, JSON.parse(JSON.stringify(buildVectors())),
    'run node tool/publication/vectors.mjs');
});

test("node's Argon2id matches RFC 9106", () => {
  const v = vectors.argon2idRfc9106;
  const tag = crypto.argon2Sync('argon2id', {
    message: Buffer.from(v.password, 'hex'),
    nonce: Buffer.from(v.salt, 'hex'),
    secret: Buffer.from(v.secret, 'hex'),
    associatedData: Buffer.from(v.associatedData, 'hex'),
    parallelism: v.p,
    tagLength: v.tagLength,
    memory: v.m,
    passes: v.t,
  });
  assert.equal(tag.toString('hex'), v.tag);
});

test("node's HKDF-SHA256 matches RFC 5869 test case 1", () => {
  const okm = crypto.hkdfSync('sha256', Buffer.alloc(22, 0x0b),
    Buffer.from('000102030405060708090a0b0c', 'hex'), Buffer.from('f0f1f2f3f4f5f6f7f8f9', 'hex'), 42);
  assert.equal(Buffer.from(okm).toString('hex'),
    '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865');
});

test('argon2id vectors', () => {
  for (const v of vectors.argon2id) {
    assert.equal(passwordKek(v.password, { salt: bytes(v.salt), m: v.m, t: v.t, p: v.p }).toString('hex'), v.kek, v.name);
  }
});

test('a password typed composed or decomposed is one password', () => {
  const composed = vectors.argon2id.find((v) => v.name === 'NFC, composed');
  const decomposed = vectors.argon2id.find((v) => v.name === 'NFC, decomposed');
  assert.notEqual(composed.passwordUtf8Hex, decomposed.passwordUtf8Hex);
  const kek = (v) => passwordKek(v.password, { salt: bytes(composed.salt), m: v.m, t: v.t, p: v.p }).toString('hex');
  assert.equal(kek(composed), kek(decomposed));
});

test('owner key vectors', () => {
  for (const v of vectors.ownerKek) {
    assert.equal(ownerKek(bytes(v.driveKey), v.publicationId).toString('hex'), v.kek);
  }
});

test('wrap vectors unwrap, and only under their own publication', () => {
  for (const v of vectors.wrap) {
    const kek = Buffer.from(v.kek, 'hex');
    assert.equal(unwrapKey(kek, bytes(v.iv), bytes(v.wrapped), v.publicationId).toString('base64url'), v.publicationKey);
    assert.throws(() => unwrapKey(kek, bytes(v.iv), bytes(v.wrapped), crypto.randomUUID()),
      (e) => e instanceof SealError && e.code === 'no-match');
  }
});

test('each page opens by link, typed key, password and owner, to the same block', () => {
  for (const v of vectors.pages) {
    const config = JSON.parse(v.publicationJson);
    const sealedBytes = bytes(v.sealed);
    const expected = JSON.parse(v.sealedPlaintext);
    const ways = [
      ['link', { linkKey: v.linkKey }],
      ['key', { input: v.linkKey }],
      ['owner', { driveKey: bytes(v.driveKey) }],
      ...(v.password != null ? [['password', { input: v.password }]] : []),
    ];
    for (const [via, given] of ways) {
      const opened = openPage({ config, sealedBytes, ...given });
      assert.equal(opened.via, via, `${v.name} via ${via}`);
      assert.deepEqual(opened.block, expected, `${v.name} via ${via}`);
      assert.equal(opened.publicationKey.toString('base64url'), v.linkKey);
    }
    assert.equal(canonicalJson(expected), v.sealedPlaintext);
  }
});

test('a page with no password slot is not opened by a password', () => {
  const v = vectors.pages.find((p) => p.password == null);
  assert.throws(() => openPage({ config: JSON.parse(v.publicationJson), sealedBytes: bytes(v.sealed), input: 'correct horse battery staple' }),
    (e) => e instanceof SealError && e.code === 'no-match');
});

test('refusals', () => {
  for (const v of vectors.refusals) {
    assert.throws(
      () => openPage({
        config: JSON.parse(v.publicationJson),
        sealedBytes: bytes(v.sealed),
        linkKey: v.linkKey,
        input: v.input,
        driveKey: v.driveKey ? bytes(v.driveKey) : undefined,
      }),
      (e) => e instanceof SealError && e.code === v.error,
      v.name,
    );
  }
});

test('the out-of-bounds slots would open their page if a reader ran them', () => {
  for (const v of vectors.refusals.filter((r) => r.outOfBounds)) {
    const config = JSON.parse(v.publicationJson);
    const slot = config.slots[0];
    const kek = crypto.argon2Sync('argon2id', {
      message: Buffer.from(v.input.normalize('NFC'), 'utf8'), nonce: bytes(slot.salt),
      parallelism: slot.p, tagLength: 32, memory: slot.m, passes: slot.t,
    });
    const key = unwrapKey(kek, bytes(slot.iv), bytes(slot.wrapped), config.publicationId);
    assert.ok(openPage({ config, sealedBytes: bytes(v.sealed), input: key.toString('base64url') }), v.name);
  }
});

test('keys have one spelling', () => {
  const key = crypto.randomBytes(32).toString('base64url');
  assert.ok(looksLikeKey(key));
  assert.equal(fromB64u(key, { bytes: 32, what: 'k' }).length, 32);
  assert.throws(() => fromB64u(`${key}=`, { bytes: 32, what: 'k' }), SealError);
  // The last character of 32 bytes carries two unused bits: setting one
  // decodes to the same bytes, and must still be refused.
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  const loose = key.slice(0, -1) + alphabet[alphabet.indexOf(key.at(-1)) ^ 1];
  assert.deepEqual(Buffer.from(loose, 'base64url'), Buffer.from(key, 'base64url'));
  assert.throws(() => fromB64u(loose, { bytes: 32, what: 'k' }), SealError);
  assert.ok(!looksLikeKey('correct horse battery staple'));
});

test('canonical JSON sorts keys at every depth', () => {
  assert.equal(canonicalJson({ b: [{ d: 1, c: 2 }], a: 'x' }), '{"a":"x","b":[{"c":2,"d":1}]}');
});
