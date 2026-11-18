import { normalizeForComparison } from './text_normalizer.js';

export const TOKEN_REGEX_SOURCE = String.raw`\[[A-Z]+(?:_[A-Z]+)*_\d+\]`;
const NEUTRALIZED_TOKEN_REGEX = /［[A-Z]+(?:_[A-Z]+)*_\d+］/g;

const CORRUPTED_OR_UNRESOLVED_REGEX = new RegExp(
  String.raw`\[[A-Z]+(?:_[A-Z]+)*(?:_|\s+|-)\d+\]` +
    String.raw`|【[A-Z]+(?:_[A-Z]+)*(?:_|\s+|-)\d+】` +
    String.raw`|(?<!［)\b(?:STUDENT|TEACHER|PERSON|EMAIL|PHONE|POSTAL|STUDENT_ID|ID)(?:_|\s+|-)\d+\b(?!］)`,
  'g',
);

export class MaskingSession {
  #keyToToken = new Map();
  #tokenToValue = new Map();
  #counters = new Map();

  static neutralizeTokens(input) {
    const str = String(input ?? '');
    if (!str) return str;
    return str.replace(
      new RegExp(TOKEN_REGEX_SOURCE, 'g'),
      (raw) => `［${raw.slice(1, -1)}］`,
    );
  }

  get tokenToValue() {
    return Object.freeze(Object.fromEntries(this.#tokenToValue));
  }

  get hasMaskedData() {
    return this.#tokenToValue.size > 0;
  }

  get maskedCount() {
    return this.#tokenToValue.size;
  }

  tokenFor(value, { prefix, canonicalKey } = {}) {
    const str = String(value ?? '');
    const trimmed = str.trim();
    if (!trimmed && !canonicalKey) return str;

    const normalizedKey = normalizeForComparison(canonicalKey ?? trimmed)
      .trim()
      .toLowerCase();
    const lookupKey = `${prefix}:${normalizedKey}`;

    const existing = this.#keyToToken.get(lookupKey);
    if (existing) return existing;

    const nextIndex = (this.#counters.get(prefix) ?? 0) + 1;
    this.#counters.set(prefix, nextIndex);
    const token = `[${prefix}_${nextIndex}]`;

    this.#keyToToken.set(lookupKey, token);
    this.#tokenToValue.set(token, trimmed || str);
    return token;
  }

  restore(text) {
    const str = String(text ?? '');
    if (!str || this.#tokenToValue.size === 0) return str;
    return str.replace(
      new RegExp(TOKEN_REGEX_SOURCE, 'g'),
      (token) => this.#tokenToValue.get(token) ?? token,
    );
  }

  findUnresolvedTokens(text) {
    const str = String(text ?? '');
    if (!str) return [];
    const cleaned = str.replace(NEUTRALIZED_TOKEN_REGEX, ' ');
    const found = [];
    for (const match of cleaned.matchAll(CORRUPTED_OR_UNRESOLVED_REGEX)) {
      const token = match[0];
      if (token && !found.includes(token)) {
        found.push(token);
      }
    }
    return found;
  }

  toString() {
    return `MaskingSession(maskedCount: ${this.#tokenToValue.size})`;
  }
}
