import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ERROR_REASONS } from '../shared/error_reasons.js';
import { DEFAULT_SCHOOL_POLICY } from '../school/policy.js';
import { SHARED_JSON_FILES } from '../scripts/sync_shared.mjs';
import { MaskingSession } from '../privacy/masking_session.js';
import { maskText } from '../privacy/anonymizer_service.js';

const ROOT_SHARED_DIR = new URL('../../shared/', import.meta.url);
const FN_SHARED_DIR = new URL('../shared/', import.meta.url);
const PRIVACY_FIXTURES_PATH = new URL('../../test_fixtures/privacy_cases.json', import.meta.url);

test('shared/*.json (source of truth) matches functions/shared/*.json without drift', () => {
  for (const file of SHARED_JSON_FILES) {
    const rootRaw = readFileSync(new URL(file, ROOT_SHARED_DIR), 'utf8');
    const fnRaw = readFileSync(new URL(file, FN_SHARED_DIR), 'utf8');
    const rootJson = JSON.parse(rootRaw);
    const fnJson = JSON.parse(fnRaw);
    assert.deepEqual(
      fnJson,
      rootJson,
      `${file} in functions/shared/ drifted from root shared/. Run: cd functions && npm run sync-shared`,
    );
    assert.equal(
      fnRaw.trimEnd(),
      rootRaw.trimEnd(),
      `${file} raw formatting drifted from root shared/. Run: cd functions && npm run sync-shared`,
    );
  }
});

test('runtime constants match shared JSON source of truth', () => {
  const reasons = JSON.parse(readFileSync(new URL('error_reasons.json', ROOT_SHARED_DIR), 'utf8'));
  const policyDefaults = JSON.parse(readFileSync(new URL('school_policy_defaults.json', ROOT_SHARED_DIR), 'utf8'));
  assert.deepEqual(ERROR_REASONS, reasons);
  assert.deepEqual(DEFAULT_SCHOOL_POLICY, policyDefaults);
});

test('test_fixtures/privacy_cases.json stays valid and passes JS masking parity', () => {
  const cases = JSON.parse(readFileSync(PRIVACY_FIXTURES_PATH, 'utf8'));
  assert.ok(Array.isArray(cases) && cases.length >= 10);
  for (const c of cases) {
    const session = new MaskingSession();
    const masked = maskText(c.input, c.people, session, { extraPatterns: c.extraPatterns });
    assert.equal(masked, c.expectedMasked, `Mask mismatch for ${c.id}`);
    assert.equal(session.restore(masked), c.expectedRestored, `Restore mismatch for ${c.id}`);
  }
});
