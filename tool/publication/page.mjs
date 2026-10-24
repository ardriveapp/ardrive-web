// The files a publication adds to a release (docs/PUBLICATIONS.md, "What a
// page is"): publication.json, the page's index.html, files.html,
// sitemap.xml and the manifest, and the tags that make the manifest an ArFS
// Publication entity (docs/ArweaveFS.md, "Publication").
//
// Pure functions, no network: build_test_page.mjs fetches and uploads. This
// is the reference the app's publisher must match byte for byte
// (golden.mjs), so every output here is deterministic: fixed key order,
// sorted maps, two-space JSON with a final newline.

/**
 * 105 KiB: Turbo's free size, before free uploads were restricted. Every
 * file a page adds stays under it.
 */
export const FREE_UPLOAD_BYTES = 107520;

export const ARFS_VERSION = '0.15';

/** The publication.json version this tool writes. */
export const PUBLICATION_VERSION = 1;

/**
 * The tags that make a publication's manifest the entity. The uploader adds
 * Content-Type, the app tags and Unix-Time.
 */
export function publicationEntityTags({ driveId, publicationId, folderId }) {
  return [
    { name: 'ArFS', value: ARFS_VERSION },
    { name: 'Entity-Type', value: 'publication' },
    { name: 'Drive-Id', value: driveId },
    { name: 'Publication-Id', value: publicationId },
    { name: 'Publication-Scope', value: folderId ?? 'drive' },
    { name: 'Publication-Version', value: String(PUBLICATION_VERSION) },
  ];
}

/** The tags of every other file a publication adds: not entities. */
export function publicationPartTags(publicationId) {
  return [{ name: 'Publication-Id', value: publicationId }];
}

const json = (value) => `${JSON.stringify(value, null, 2)}\n`;

const sorted = (map) =>
  Object.fromEntries(Object.entries(map).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));

/** The most files `files.html` and `sitemap.xml` list. */
export const FILES_PAGE_CAP = 5000;

/**
 * publication.json. `snapshot.tags` is every tag of the artifact, which the
 * viewer builds its import candidate from instead of GraphQL. `fileCount`
 * (what the publication lists, for its owner), `keywords` and `license` are
 * written only when set.
 */
export function buildPublicationJson({
  driveId,
  rootFolderId,
  folderId,
  privacy,
  owner,
  ownerName,
  snapshotTxId,
  snapshotTags,
  title,
  description,
  fileCount,
  keywords,
  license,
  images,
  generatedCard,
  publishedAt,
  viewer,
}) {
  const config = {
    version: PUBLICATION_VERSION,
    driveId,
    rootFolderId,
    scope: folderId ? { type: 'folder', folderId } : { type: 'drive' },
    privacy,
    owner,
    ...(ownerName ? { ownerName } : {}),
    snapshot: { path: 'snapshot', txId: snapshotTxId, tags: sorted(snapshotTags) },
    title,
    description,
  };
  if (fileCount != null) config.fileCount = fileCount;
  if (keywords?.length) config.keywords = keywords;
  if (license) config.license = license;
  if (images && Object.keys(images).length) config.images = images;
  if (generatedCard) config.generatedSocialCard = true;
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
 * card. Without icons the release's own stay. With `filesPage`, a crawler
 * that runs no script finds `files.html` (and the head names `sitemap.xml`).
 */
export function buildIndexHtml(
  releaseIndexHtml,
  { title, description, icons, socialImageUrl, filesPage },
) {
  let html = releaseIndexHtml;
  for (const pattern of [...REPLACED, ...(icons ? ICON_LINKS : [])]) {
    html = html.replace(pattern, '');
  }
  const charset = /<meta charset="[^"]*"\s*\/?>/i.exec(html);
  if (!charset) throw new Error('release index.html has no <meta charset>');

  const e = escapeHtml;
  const head = [
    '<meta name="ardrive-publication" content="publication.json">',
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
  if (filesPage) {
    head.push('<link rel="sitemap" type="application/xml" href="sitemap.xml">');
  }
  const at = charset.index + charset[0].length;
  html = `${html.slice(0, at)}\n${head.map((line) => `    ${line}`).join('\n')}${html.slice(at)}`;
  if (filesPage) {
    const body = /<body[^>]*>/i.exec(html);
    if (!body) throw new Error('release index.html has no <body>');
    const end = body.index + body[0].length;
    const link = `\n    <noscript><a href="files.html">${e(filesPage.label)}</a></noscript>`;
    html = `${html.slice(0, end)}${link}${html.slice(end)}`;
  }
  return html;
}

const byName = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);

/**
 * `files.html`: every file of the page as a link to its data on the
 * gateway, folders nested, for search engines and anything else that runs
 * no script. `files` are `{ path: [folder, ..., name], id }`, the path
 * relative to the page's top folder. Lists at most FILES_PAGE_CAP files, the
 * first in that order.
 */
export function buildFilesHtml({ title, files, gateway, labels }) {
  const e = escapeHtml;
  const listed = files.slice(0, FILES_PAGE_CAP);
  const root = { name: '', folders: new Map(), files: [] };
  for (const file of listed) {
    let folder = root;
    for (const name of file.path.slice(0, -1)) {
      if (!folder.folders.has(name)) {
        folder.folders.set(name, { name, folders: new Map(), files: [] });
      }
      folder = folder.folders.get(name);
    }
    folder.files.push({ name: file.path.at(-1), id: file.id });
  }
  const lines = [];
  const list = (folder, depth) => {
    const pad = '  '.repeat(depth);
    lines.push(`${pad}<ul>`);
    for (const child of [...folder.folders.values()].sort(byName)) {
      lines.push(`${pad}  <li>${e(child.name)}`);
      list(child, depth + 2);
      lines.push(`${pad}  </li>`);
    }
    for (const file of [...folder.files].sort(byName)) {
      lines.push(`${pad}  <li><a href="${e(`${gateway}/${file.id}`)}">${e(file.name)}</a></li>`);
    }
    lines.push(`${pad}</ul>`);
  };
  list(root, 1);
  const more = files.length - listed.length;
  return [
    '<!DOCTYPE html>',
    '<html>',
    '<head>',
    '  <meta charset="UTF-8">',
    '  <meta name="viewport" content="width=device-width, initial-scale=1">',
    `  <title>${e(title)}</title>`,
    '</head>',
    '<body>',
    `  <h1>${e(title)}</h1>`,
    `  <p><a href="./">${e(labels.open)}</a></p>`,
    ...lines,
    ...(more > 0 ? [`  <p>${e(labels.more.replace('{count}', String(more)))}</p>`] : []),
    '</body>',
    '</html>',
    '',
  ].join('\n');
}

/** `sitemap.xml`: the same files as `files.html`, as gateway data links. */
export function buildSitemap({ files, gateway }) {
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...files
      .slice(0, FILES_PAGE_CAP)
      .map((file) => `  <url><loc>${escapeHtml(`${gateway}/${file.id}`)}</loc></url>`),
    '</urlset>',
    '',
  ].join('\n');
}

/**
 * The page manifest: every path of the release, then the page's own paths
 * over them, sorted; index.html is the index and the fallback.
 */
export function buildManifest(releaseManifest, pagePaths) {
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
