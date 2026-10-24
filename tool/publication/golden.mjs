// The golden files the app's publisher is held to
// (test/publication/domain/publication_files_test.dart): this tool's output for
// the inputs in test/publication/fixtures/golden/inputs.json.
//
//   node tool/publication/golden.mjs          # rewrites the golden files
//   node --test tool/publication/page.test.mjs # checks they are current

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  buildFilesHtml,
  buildIndexHtml,
  buildPublicationJson,
  buildManifest,
  publicationEntityTags,
  publicationPartTags,
  buildSitemap,
} from './page.mjs';

export const GOLDEN_DIR = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../test/publication/fixtures/golden',
);

export function goldenFiles() {
  const input = JSON.parse(fs.readFileSync(path.join(GOLDEN_DIR, 'inputs.json'), 'utf8'));
  const { publication, gateway, labels, files } = input;
  return {
    'publication.json': buildPublicationJson(publication),
    'index.html': buildIndexHtml(input.releaseIndexHtml, {
      title: publication.title,
      description: publication.description,
      icons: { small: 'icon-32.png', touch: 'icon-180.png' },
      socialImageUrl: input.socialImageUrl,
      filesPage: { label: labels.filesPage },
    }),
    'files.html': buildFilesHtml({ title: publication.title, files, gateway, labels }),
    'sitemap.xml': buildSitemap({ files, gateway }),
    'tags.json': `${JSON.stringify({
      entity: publicationEntityTags({ ...publication, publicationId: input.publicationId }),
      part: publicationPartTags(input.publicationId),
    }, null, 2)}\n`,
    'manifest.json': buildManifest(
      input.releaseManifest,
      Object.fromEntries(Object.entries(input.pagePaths).map(([name, id]) => [name, { id }])),
    ),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  for (const [name, text] of Object.entries(goldenFiles())) {
    fs.writeFileSync(path.join(GOLDEN_DIR, `${name}.golden`), text);
  }
  console.log(`wrote the golden files to ${GOLDEN_DIR}`);
}
