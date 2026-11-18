// Copies root `shared/*.json` (Single Source of Truth) into `functions/shared/`
// because Cloud Functions deploy uploads only the `functions/` directory.
// Run after editing `shared/*.json`: `cd functions && npm run sync-shared`
// `test/shared_sync.test.js` and Dart `shared_sync_test.dart` fail on any drift.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const ROOT_SHARED_DIR = fileURLToPath(new URL('../../shared/', import.meta.url));
const FN_SHARED_DIR = fileURLToPath(new URL('../shared/', import.meta.url));

export const SHARED_JSON_FILES = Object.freeze([
  'error_reasons.json',
  'school_policy_defaults.json',
]);

export function syncSharedJsonFiles() {
  const synced = [];
  for (const file of SHARED_JSON_FILES) {
    const src = `${ROOT_SHARED_DIR}${file}`;
    const dst = `${FN_SHARED_DIR}${file}`;
    const raw = readFileSync(src, 'utf8');
    // Validate JSON syntax before copying.
    JSON.parse(raw);
    writeFileSync(dst, raw.endsWith('\n') ? raw : `${raw}\n`, 'utf8');
    synced.push(file);
  }
  return synced;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const synced = syncSharedJsonFiles();
  console.log(`Synced shared JSON files to functions/shared/: ${synced.join(', ')}`);
}
