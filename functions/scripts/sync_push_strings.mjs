// Copies the push_* keys of every app locale (assets/l10n/*.json) into
// functions/school/push_strings.json. Cloud Functions deploy only the
// functions/ folder, so the server keeps its own copy of these strings.
// Run after editing push_* keys: `npm run sync-push-strings` in functions/.
// test/push_i18n.test.js fails when the copy is out of date.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const l10nDir = fileURLToPath(new URL('../../assets/l10n/', import.meta.url));
const outFile = fileURLToPath(new URL('../school/push_strings.json', import.meta.url));

export function collectPushStrings() {
  const out = {};
  for (const file of readdirSync(l10nDir).filter((f) => f.endsWith('.json')).sort()) {
    const all = JSON.parse(readFileSync(l10nDir + file, 'utf8'));
    out[file.slice(0, -5)] = Object.fromEntries(
      Object.entries(all).filter(([k]) => k.startsWith('push_')).sort(([a], [b]) => a.localeCompare(b)),
    );
  }
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  writeFileSync(outFile, `${JSON.stringify(collectPushStrings(), null, 2)}\n`);
  console.log(`wrote ${outFile}`);
}
