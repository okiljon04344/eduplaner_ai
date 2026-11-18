import { readFileSync } from 'node:fs';

/**
 * Shared error `details.reason` constants loaded from `error_reasons.json`.
 * Parity with root `shared/error_reasons.json` is enforced by unit tests.
 */
export const ERROR_REASONS = Object.freeze(
  JSON.parse(readFileSync(new URL('./error_reasons.json', import.meta.url), 'utf8')),
);
