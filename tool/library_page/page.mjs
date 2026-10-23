// The three files a library page adds to a release: library.json, the page's
// index.html and the page manifest (docs/LIBRARY_PAGES.md, "What a page is").
//
// Pure functions, no network: build_test_page.mjs fetches and uploads. This
// is the reference the app's publisher (phase 2) must match byte for byte, so
// every output here is deterministic: fixed key order, sorted maps, two-space
// JSON with a final newline.

/**
 * 105 KiB: Turbo's free size, before free uploads were restricted. Every
 * file a page adds stays under it.
 */
export const FREE_UPLOAD_BYTES = 107520;

/** The `Type` tag of each upload (docs/LIBRARY_PAGES.md, "Tags"). */
export const PAGE_TYPES = {
  manifest: 'library-page',
  config: 'library-config',
  index: 'library-index',
  asset: 'library-asset',
};

const json = (value) => `${JSON.stringify(value, null, 2)}\n`;

const sorted = (map) =>
  Object.fromEntries(Object.entries(map).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));

/**
 * library.json. `snapshot.tags` is every tag of the artifact, which the
 * viewer builds its import candidate from instead of GraphQL.
 */
export function buildLibraryJson({
  driveId,
  rootFolderId,
  folderId,
  privacy,
  owner,
  snapshotTxId,
  snapshotTags,
  title,
  description,
  images,
  publishedAt,
  viewer,
}) {
  const config = {
    version: 1,
    driveId,
    rootFolderId,
    scope: folderId ? { type: 'folder', folderId } : { type: 'drive' },
    privacy,
    owner,
    snapshot: { path: 'snapshot', txId: snapshotTxId, tags: sorted(snapshotTags) },
    title,
    description,
  };
  if (images && Object.keys(images).length) config.images = images;
  config.publishedAt = publishedAt;
  if (viewer) config.viewer = { release: viewer.release, manifest: viewer.manifest };
  return json(config);
}

export function escapeHtml(text) {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

// What the page writes is left out of the release's head first, so a scraper
// never sees two titles or ArDrive's own card. One-line tags only, which is
// how web/index.html writes them; its comments mention tags but are not tags.
const REPLACED = [
  /^[ \t]*<title>[^<]*<\/title>[ \t]*\r?\n/gm,
  /^[ \t]*<meta name="description"[^>]*>[ \t]*\r?\n/gm,
  /^[ \t]*<meta name="theme-color"[^>]*>[ \t]*\r?\n/gm,
  /^[ \t]*<meta property="og:[^>]*>[ \t]*\r?\n/gm,
  /^[ \t]*<meta name="twitter:[^>]*>[ \t]*\r?\n/gm,
];
const ICON_LINKS = [
  /^[ \t]*<link rel="(?:shortcut )?icon"[^>]*>[ \t]*\r?\n/gm,
  /^[ \t]*<link rel="apple-touch-icon"[^>]*>[ \t]*\r?\n/gm,
];

/**
 * The release's index.html with the page's head written in, right after
 * `<meta charset>`. `socialImageUrl` is the absolute URL of the social
 * image's own transaction; without one there is no og:image and no large
 * card. Without icons the release's own stay.
 */
export function buildIndexHtml(releaseIndexHtml, { title, description, icons, socialImageUrl }) {
  let html = releaseIndexHtml;
  for (const pattern of [...REPLACED, ...(icons ? ICON_LINKS : [])]) {
    html = html.replace(pattern, '');
  }
  const charset = /<meta charset="[^"]*"\s*\/?>/i.exec(html);
  if (!charset) throw new Error('release index.html has no <meta charset>');

  const e = escapeHtml;
  const head = [
    '<meta name="ardrive-library" content="library.json">',
    `<title>${e(title)}</title>`,
    `<meta name="description" content="${e(description)}">`,
    '<meta name="theme-color" content="#F7F7F7" media="(prefers-color-scheme: light)">',
    '<meta name="theme-color" content="#080808" media="(prefers-color-scheme: dark)">',
  ];
  if (icons) {
    head.push(`<link rel="icon" sizes="32x32" href="${e(icons.small)}">`);
    head.push(`<link rel="apple-touch-icon" href="${e(icons.touch)}">`);
  }
  head.push(
    `<meta property="og:title" content="${e(title)}">`,
    `<meta property="og:description" content="${e(description)}">`,
    '<meta property="og:type" content="website">',
  );
  if (socialImageUrl) {
    head.push(
      `<meta property="og:image" content="${e(socialImageUrl)}">`,
      '<meta name="twitter:card" content="summary_large_image">',
    );
  }
  const at = charset.index + charset[0].length;
  return `${html.slice(0, at)}\n${head.map((line) => `    ${line}`).join('\n')}${html.slice(at)}`;
}

/**
 * The page manifest: every path of the release, then the page's own paths
 * over them, sorted; index.html is the index and the fallback.
 */
export function buildPageManifest(releaseManifest, pagePaths) {
  if (releaseManifest.manifest !== 'arweave/paths') {
    throw new Error('the release is not an arweave/paths manifest');
  }
  const paths = sorted({ ...releaseManifest.paths, ...pagePaths });
  const index = paths['index.html'];
  if (!index) throw new Error('the page has no index.html');
  return json({
    manifest: 'arweave/paths',
    version: '0.2.0',
    index: { path: 'index.html' },
    fallback: { id: index.id },
    paths,
  });
}
