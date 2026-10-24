// node --test tool/publication/page.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildIndexHtml, buildPublicationJson, buildManifest, escapeHtml } from './page.mjs';

const release = `<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8" />
    <meta name="description" content="ArDrive is a permanent home." />
    <!-- <meta property="og:title" content="in a comment"> -->
    <meta property="og:title" content="ArDrive">
    <meta property="og:image" content="https://arweave.net/raw/card">
    <meta name="twitter:card" content="summary_large_image">
    <link rel="shortcut icon" type="image/png" href="favicon.png" />
    <title>ArDrive</title>
  </head>
</html>
`;

test('escapes everything an owner types', () => {
  assert.equal(escapeHtml(`<a href="x">'&'</a>`), '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;');
});

test("index.html replaces the release's head with the page's", () => {
  const html = buildIndexHtml(release, { title: 'Phil\'s <Archive>', description: 'A "quote".' });
  assert.match(html, /<meta charset="UTF-8" \/>\n {4}<meta name="ardrive-publication" content="publication.json">/);
  assert.match(html, /<title>Phil&#39;s &lt;Archive&gt;<\/title>/);
  assert.match(html, /<meta property="og:description" content="A &quot;quote&quot;.">/);
  assert.doesNotMatch(html, /<title>ArDrive<\/title>/);
  assert.doesNotMatch(html, /permanent home/);
  // No social image: no card image and no large card.
  assert.doesNotMatch(html, /og:image|twitter:card/);
  // Comments are left alone, and so are the release's icons when the page
  // has none.
  assert.match(html, /<!-- <meta property="og:title" content="in a comment"> -->/);
  assert.match(html, /favicon\.png/);
});

test('index.html names a social image by its own transaction', () => {
  const html = buildIndexHtml(release, {
    title: 't',
    description: 'd',
    socialImageUrl: 'https://turbo-gateway.com/social-image-id',
    icons: { small: 'icon-32.png', touch: 'icon-180.png' },
  });
  assert.match(html, /<meta property="og:image" content="https:\/\/turbo-gateway.com\/social-image-id">/);
  assert.match(html, /<meta name="twitter:card" content="summary_large_image">/);
  assert.equal(html.match(/twitter:card/g).length, 1);
  assert.doesNotMatch(html, /favicon\.png/);
  assert.match(html, /<link rel="icon" sizes="32x32" href="icon-32.png">/);
});

test('publication.json has a fixed shape', () => {
  const text = buildPublicationJson({
    driveId: 'd',
    rootFolderId: 'r',
    folderId: 'f',
    privacy: 'public',
    owner: 'o',
    snapshotTxId: 's',
    snapshotTags: { 'Entity-Type': 'drive-state', 'Drive-Id': 'd' },
    title: 'T',
    description: '',
    publishedAt: '2026-10-23T00:00:00Z',
  });
  assert.equal(text.at(-1), '\n');
  const config = JSON.parse(text);
  assert.deepEqual(Object.keys(config), [
    'version', 'driveId', 'rootFolderId', 'scope', 'privacy', 'owner',
    'snapshot', 'title', 'description', 'publishedAt',
  ]);
  assert.deepEqual(config.scope, { type: 'folder', folderId: 'f' });
  assert.equal('ownerName' in config, false);
  const named = JSON.parse(buildPublicationJson({ ...JSON.parse(text), snapshotTags: {}, ownerName: 'Phil' }));
  assert.deepEqual(Object.keys(named).slice(5, 8), ['owner', 'ownerName', 'snapshot']);
  assert.deepEqual(Object.keys(config.snapshot.tags), ['Drive-Id', 'Entity-Type']);
});

test('the manifest is the release with the page over it', () => {
  const manifest = JSON.parse(
    buildManifest(
      {
        manifest: 'arweave/paths',
        version: '0.2.0',
        index: { path: 'index.html' },
        paths: { 'main.dart.js': { id: 'main' }, 'index.html': { id: 'release-index' } },
      },
      { 'index.html': { id: 'page-index' }, 'publication.json': { id: 'config' }, snapshot: { id: 'snap' } },
    ),
  );
  assert.deepEqual(manifest.index, { path: 'index.html' });
  assert.deepEqual(manifest.fallback, { id: 'page-index' });
  assert.deepEqual(Object.keys(manifest.paths), ['index.html', 'main.dart.js', 'publication.json', 'snapshot']);
  assert.equal(manifest.paths['index.html'].id, 'page-index');
});

test('the golden files the app is held to are current', async () => {
  const fs = await import('node:fs');
  const path = await import('node:path');
  const { GOLDEN_DIR, goldenFiles } = await import('./golden.mjs');
  for (const [name, text] of Object.entries(goldenFiles())) {
    assert.equal(fs.readFileSync(path.join(GOLDEN_DIR, `${name}.golden`), 'utf8'), text, name);
  }
});
