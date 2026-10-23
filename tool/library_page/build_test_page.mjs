#!/usr/bin/env node
// Builds a library page by hand (docs/library-pages/IMPLEMENTATION_PLAN.md,
// phase 1.5): library.json, the page's index.html and the page manifest, from
// a release, a drive and a snapshot already on Arweave.
//
//   npm ci --prefix tool/library_page
//   node tool/library_page/build_test_page.mjs \
//     --release <release manifest id> --snapshot <artifact tx id> \
//     --root <root folder id> [--folder <folder id>] \
//     --title 'A title' [--description 'A sentence.'] [--owner-name 'Name'] \
//     [--images <dir>] [--gateway turbo-gateway.com] [--out <dir>] [--upload]
//
// The drive, its owner and privacy come from the artifact's tags, read once
// from the gateway's GraphQL. Without --upload it writes the three files to
// --out (default library-page-out/) and stops; the manifest then names the
// page's own files by placeholder IDs. With --upload it uploads library.json
// and index.html, then the manifest naming them, with Turbo, signed by the
// wallet ARDRIVE_E2E_KEYFILE names in ~/.config/ardrive-e2e/env (or
// CREDENTIALS), and prints the page link and what each upload cost. Each
// file must be under 105 KiB, Turbo's free size before free uploads were
// restricted; the test wallet now pays for them, about 0.0014 credits a
// page (October 2026).
//
// --images names a directory holding any of the page's images, already
// sized: icon-32.png, icon-180.png and icon-512.png (all three or none),
// social.jpg (1200 x 630) and cover.jpg (1600 x 400). Each is uploaded on its
// own first, so the social card's link is known before index.html is written.
//
// Public drives only, until private pages (phase 3).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { gunzipSync } from 'node:zlib';
import { parseArgs } from 'node:util';
import {
  FREE_UPLOAD_BYTES,
  PAGE_TYPES,
  buildIndexHtml,
  buildLibraryJson,
  buildPageManifest,
} from './page.mjs';

const ID = /^[A-Za-z0-9_-]{43}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const { values: args } = parseArgs({
  options: {
    release: { type: 'string' },
    snapshot: { type: 'string' },
    root: { type: 'string' },
    folder: { type: 'string' },
    title: { type: 'string' },
    description: { type: 'string', default: '' },
    'owner-name': { type: 'string' },
    images: { type: 'string' },
    gateway: { type: 'string', default: 'turbo-gateway.com' },
    out: { type: 'string', default: 'library-page-out' },
    upload: { type: 'boolean', default: false },
  },
});

function fail(message) {
  console.error(message);
  process.exit(2);
}

if (!ID.test(args.release ?? '')) fail('--release must be a manifest transaction ID');
if (!ID.test(args.snapshot ?? '')) fail('--snapshot must be an artifact transaction ID');
if (!UUID.test(args.root ?? '')) fail('--root must be the drive\'s root folder ID');
if (args.folder && !UUID.test(args.folder)) fail('--folder must be a folder ID');
if (!args.title?.trim()) fail('--title is required');

const gateway = `https://${args.gateway}`;

const IMAGE_FILES = {
  'icon-32.png': 'image/png',
  'icon-180.png': 'image/png',
  'icon-512.png': 'image/png',
  'social.jpg': 'image/jpeg',
  'cover.jpg': 'image/jpeg',
};
const images = args.images
  ? Object.fromEntries(
      Object.keys(IMAGE_FILES)
        .filter((name) => fs.existsSync(path.join(args.images, name)))
        .map((name) => [name, fs.readFileSync(path.join(args.images, name))]),
    )
  : {};
const icons = ['icon-32.png', 'icon-180.png', 'icon-512.png'].filter((name) => images[name]);
if (icons.length !== 0 && icons.length !== 3) fail('--images needs all three icon sizes or none');
for (const [name, data] of Object.entries(images)) {
  if (data.length >= FREE_UPLOAD_BYTES) fail(`${name} is ${data.length} bytes, over 105 KiB`);
}
/** library.json's `images`: the paths the page has. */
const imagePaths = {
  ...(icons.length ? { icon: 'icon-512.png' } : {}),
  ...(images['social.jpg'] ? { social: 'social.jpg' } : {}),
  ...(images['cover.jpg'] ? { cover: 'cover.jpg' } : {}),
};

async function get(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  // The release is stored gzipped; a gateway that sends it without
  // Content-Encoding leaves fetch to hand over the compressed bytes.
  return bytes[0] === 0x1f && bytes[1] === 0x8b ? gunzipSync(bytes) : bytes;
}

async function artifact(id) {
  const query = `{ transactions(ids: ["${id}"]) { edges { node {
    id owner { address } tags { name value } } } } }`;
  const response = await fetch(`${gateway}/graphql`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  if (!response.ok) throw new Error(`GraphQL: HTTP ${response.status}`);
  const node = (await response.json()).data?.transactions?.edges?.[0]?.node;
  if (!node) throw new Error(`${id} is not indexed on ${args.gateway} yet`);
  return {
    owner: node.owner.address,
    tags: Object.fromEntries(node.tags.map(({ name, value }) => [name, value])),
  };
}

const snapshot = await artifact(args.snapshot);
if (snapshot.tags['Entity-Type'] !== 'drive-state') {
  fail(`${args.snapshot} is not a drive state artifact`);
}
if (snapshot.tags.Cipher) fail('private libraries arrive in phase 3');
const driveId = snapshot.tags['Drive-Id'];

const release = JSON.parse(await get(`${gateway}/raw/${args.release}`));
const releaseIndex = release.paths?.['index.html']?.id;
if (!releaseIndex) fail('the release manifest has no index.html');
const version = release.paths['version.json']
  ? JSON.parse(await get(`${gateway}/raw/${release.paths['version.json'].id}`)).version
  : undefined;

const libraryJsonOf = () => buildLibraryJson({
  driveId,
  rootFolderId: args.root,
  folderId: args.folder,
  privacy: 'public',
  owner: snapshot.owner,
  ownerName: args['owner-name']?.trim() || undefined,
  snapshotTxId: args.snapshot,
  snapshotTags: snapshot.tags,
  title: args.title,
  description: args.description,
  images: imagePaths,
  publishedAt,
  viewer: version ? { release: version, manifest: args.release } : undefined,
});
const publishedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const releaseIndexHtml = (await get(`${gateway}/raw/${releaseIndex}`)).toString('utf8');
const indexHtmlOf = (socialImageUrl) =>
  buildIndexHtml(releaseIndexHtml, {
    title: args.title,
    description: args.description,
    icons: icons.length ? { small: 'icon-32.png', touch: 'icon-180.png' } : undefined,
    socialImageUrl,
  });
const libraryJson = libraryJsonOf();
const placeholderSocial = images['social.jpg'] ? `${gateway}/SOCIAL-IMAGE` : undefined;
let indexHtml = indexHtmlOf(placeholderSocial);

for (const [name, text] of [['library.json', libraryJson], ['index.html', indexHtml]]) {
  if (Buffer.byteLength(text) >= FREE_UPLOAD_BYTES) {
    fail(`${name} is ${Buffer.byteLength(text)} bytes, over 105 KiB`);
  }
}

const out = path.resolve(args.out);
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'library.json'), libraryJson);
fs.writeFileSync(path.join(out, 'index.html'), indexHtml);

if (!args.upload) {
  const placeholder = (name) => ({ id: name.padEnd(43, '_').slice(0, 43) });
  const manifest = buildPageManifest(release, {
    'index.html': placeholder('PAGE-INDEX'),
    'library.json': placeholder('PAGE-CONFIG'),
    snapshot: { id: args.snapshot },
    ...Object.fromEntries(Object.keys(images).map((name) => [name, placeholder(name)])),
  });
  fs.writeFileSync(path.join(out, 'manifest.json'), manifest);
  console.log(`wrote library.json, index.html and manifest.json to ${out}; nothing uploaded`);
  process.exit(0);
}

const { TurboFactory } = await import('@ardrive/turbo-sdk');
const turbo = TurboFactory.authenticated({ privateKey: wallet() });

const appTags = [
  { name: 'App-Name', value: 'ArDrive-Web' },
  { name: 'App-Version', value: version ?? 'library-page-tool' },
];

async function upload(text, contentType, type, extraTags = []) {
  const data = Buffer.isBuffer(text) ? text : Buffer.from(text);
  if (data.length >= FREE_UPLOAD_BYTES) throw new Error(`${type} is over 105 KiB`);
  const receipt = await turbo.upload({
    data,
    dataItemOpts: {
      tags: [
        { name: 'Content-Type', value: contentType },
        ...appTags,
        { name: 'Type', value: type },
        ...extraTags,
      ],
    },
  });
  console.log(`${type}: ${receipt.id} (${data.length} bytes, ${receipt.winc} winc)`);
  return receipt.id;
}

// Images first: index.html names the social card by its own transaction.
const imageIds = {};
for (const [name, data] of Object.entries(images)) {
  imageIds[name] = await upload(data, IMAGE_FILES[name], PAGE_TYPES.asset);
}
if (imageIds['social.jpg']) {
  indexHtml = indexHtmlOf(`${gateway}/${imageIds['social.jpg']}`);
  fs.writeFileSync(path.join(out, 'index.html'), indexHtml);
}
const configId = await upload(libraryJson, 'application/json', PAGE_TYPES.config);
const indexId = await upload(indexHtml, 'text/html', PAGE_TYPES.index);
const manifest = buildPageManifest(release, {
  'index.html': { id: indexId },
  'library.json': { id: configId },
  snapshot: { id: args.snapshot },
  ...Object.fromEntries(Object.entries(imageIds).map(([name, id]) => [name, { id }])),
});
fs.writeFileSync(path.join(out, 'manifest.json'), manifest);
const manifestId = await upload(manifest, 'application/x.arweave-manifest+json', PAGE_TYPES.manifest, [
  { name: 'Drive-Id', value: driveId },
  { name: 'Library-Scope', value: args.folder ?? 'drive' },
  { name: 'Library-Version', value: '1' },
]);
console.log(`page: ${gateway}/${manifestId}/`);

/** The test wallet's JWK. Its path is never printed. */
function wallet() {
  const credentials =
    process.env.CREDENTIALS || path.join(os.homedir(), '.config', 'ardrive-e2e', 'env');
  const line = fs
    .readFileSync(credentials, 'utf8')
    .split('\n')
    .map((l) => l.match(/^\s*(?:export\s+)?ARDRIVE_E2E_KEYFILE\s*=\s*(.*?)\s*$/))
    .find(Boolean);
  if (!line) fail('ARDRIVE_E2E_KEYFILE is not set in the credentials file');
  const keyfile = line[1].replace(/^(['"])(.*)\1$/, '$2').replace(/^~(?=\/)/, os.homedir());
  try {
    return JSON.parse(fs.readFileSync(keyfile, 'utf8'));
  } catch {
    fail('the wallet ARDRIVE_E2E_KEYFILE names cannot be read');
  }
}
