import sharp from 'sharp';
import vision from '@google-cloud/vision';
import { HttpsError } from 'firebase-functions/https';
import { logger } from 'firebase-functions';
import {
  DEFAULT_HONORIFIC_EXCEPTIONS,
  compileRoster,
} from './anonymizer_service.js';
import { normalizeWithMap } from './text_normalizer.js';
import { boundedSchoolMatches } from './pii_pattern_masker.js';
import { validateSafeRegexPattern } from '../school/policy.js';
import { ERROR_REASONS } from '../shared/error_reasons.js';

const escapeRegExp = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export const IMAGE_REDACT_MAX_EDGE = 2048;
export const VISION_TIMEOUT_MS = 25_000;
export const REDACTION_EXPAND_RATIO = 0.2;
export const HIGH_REDACTION_AREA_THRESHOLD = 0.30;
export const NAME_LABEL_MAX_LINE_LENGTH = 12;

export const REDACTABLE_IMAGE_MIMES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
]);

const HONORIFIC_RE =
  /([\u4E00-\u9FFF\u3040-\u309F\u30A0-\u30FFー]{1,4})(さん|くん|君|ちゃん|先生|様)/g;
const LEADING_PARTICLES = new Set([
  'は', 'が', 'を', 'に', 'へ', 'と', 'で', 'や', 'の', 'も', 'か',
]);
const KANJI_OR_KATAKANA_START_RE = /^[\u4E00-\u9FFF\u30A0-\u30FF]/;

const LABEL_RE =
  /(?:氏\s*名|名\s*前|生徒名|学生名|学籍番号|出席番号|Student\s*ID|(?<![A-Za-z])Name\s*[:：])/gi;
const SHORT_LINE_NAME_LABEL_RE = /^(\s*)(Name)(?![A-Za-z])/i;

const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const PHONE_RE =
  /(?:\+81[\s-]?\d{1,4}[\s-]?\d{1,4}[\s-]?\d{3,4}|0\d{1,4}[-\sー－]\d{1,4}[-\sー－]\d{3,4})/g;
const POSTAL_RE = /〒\s*\d{3}[-\sー－]\d{4}/g;

let _visionClient = null;
let _visionClientOverride = null;

/**
 * Replaces the Vision API client for tests; pass `null` to restore default.
 */
export function setVisionClientForTest(mockClient) {
  _visionClientOverride = mockClient;
}

function getVisionClient() {
  if (_visionClientOverride) return _visionClientOverride;
  if (!_visionClient) {
    _visionClient = new vision.ImageAnnotatorClient();
  }
  return _visionClient;
}

function withTimeout(promise, ms, label) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(new Error(`${label} timed out after ${ms}ms`));
    }, ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => {
    clearTimeout(timer);
  });
}

function sharpFormatForMime(mimeType) {
  switch (mimeType) {
    case 'image/jpeg':
      return { format: 'jpeg', options: { quality: 90 } };
    case 'image/png':
      return { format: 'png', options: {} };
    case 'image/webp':
      return { format: 'webp', options: { quality: 90 } };
    default:
      return null;
  }
}

function boxFromVertices(vertices) {
  if (!Array.isArray(vertices) || vertices.length === 0) return null;
  let left = Infinity;
  let top = Infinity;
  let right = -Infinity;
  let bottom = -Infinity;
  for (const v of vertices) {
    const x = Number(v?.x ?? 0);
    const y = Number(v?.y ?? 0);
    if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
    if (x < left) left = x;
    if (y < top) top = y;
    if (x > right) right = x;
    if (y > bottom) bottom = y;
  }
  if (!Number.isFinite(left) || right <= left || bottom <= top) return null;
  return { left, top, right, bottom, width: right - left, height: bottom - top };
}

function unionBoxes(charBoxes, startIdx, endIdx) {
  let left = Infinity;
  let top = Infinity;
  let right = -Infinity;
  let bottom = -Infinity;
  for (let i = startIdx; i < endIdx && i < charBoxes.length; i++) {
    const b = charBoxes[i];
    if (!b) continue;
    if (b.left < left) left = b.left;
    if (b.top < top) top = b.top;
    if (b.right > right) right = b.right;
    if (b.bottom > bottom) bottom = b.bottom;
  }
  if (!Number.isFinite(left) || right <= left || bottom <= top) return null;
  return { left, top, right, bottom, width: right - left, height: bottom - top };
}

/**
 * Reconstructs OCR lines with per-character bounding boxes from Vision
 * `fullTextAnnotation`.
 */
export function extractOcrLines(fullTextAnnotation) {
  const lines = [];
  const pages = fullTextAnnotation?.pages ?? [];
  const asciiAlnum = /^[A-Za-z0-9]$/;

  for (const page of pages) {
    for (const block of page?.blocks ?? []) {
      for (const paragraph of block?.paragraphs ?? []) {
        let chars = [];
        let boxes = [];

        const flushLine = () => {
          if (chars.length > 0) {
            lines.push({ text: chars.join(''), boxes });
            chars = [];
            boxes = [];
          }
        };

        for (const word of paragraph?.words ?? []) {
          const symbols = word?.symbols;
          if (Array.isArray(symbols) && symbols.length > 0) {
            const firstSymChar = (symbols[0]?.text ?? '')[0] ?? '';
            const lastChar = chars.length > 0 ? chars[chars.length - 1] : '';
            if (asciiAlnum.test(lastChar) && asciiAlnum.test(firstSymChar)) {
              chars.push(' ');
              boxes.push(null);
            }
            for (const sym of symbols) {
              const txt = String(sym?.text ?? '');
              const box = boxFromVertices(sym?.boundingBox?.vertices);
              for (const ch of txt) {
                chars.push(ch);
                boxes.push(box);
              }
              const br = sym?.property?.detectedBreak?.type;
              if (br === 'SPACE' || br === 'SURE_SPACE') {
                chars.push(' ');
                boxes.push(null);
              } else if (br === 'EOL_SURE_SPACE' || br === 'LINE_BREAK') {
                flushLine();
              }
            }
          } else if (typeof word?.text === 'string' && word.text.length > 0) {
            const firstChar = word.text[0] ?? '';
            const lastChar = chars.length > 0 ? chars[chars.length - 1] : '';
            if (asciiAlnum.test(lastChar) && asciiAlnum.test(firstChar)) {
              chars.push(' ');
              boxes.push(null);
            }
            const box = boxFromVertices(word?.boundingBox?.vertices);
            for (const ch of word.text) {
              chars.push(ch);
              boxes.push(box);
            }
            const br = word?.property?.detectedBreak?.type;
            if (br === 'EOL_SURE_SPACE' || br === 'LINE_BREAK') {
              flushLine();
            } else if (br === 'SPACE' || br === 'SURE_SPACE') {
              chars.push(' ');
              boxes.push(null);
            }
          }
        }
        flushLine();
      }
    }
  }

  return lines;
}

/**
 * Computes raw (unpadded) redaction rectangles from OCR lines using:
 * 1. Known roster names (`people` from `loadPeopleForCaller`)
 * 2. Japanese honorific patterns (`〜さん`, `〜先生`, etc.)
 * 3. Printed PII patterns (email, phone, postal code, plus additive `extraPatterns`)
 * 4. Identity labels (`氏名`, `名前`, `Student ID`, plus additive `extraLabels`) -> right + below regions
 */
export function findRedactionBoxes(
  lines,
  people,
  {
    extraLabels = [],
    extraHonorificExceptions = [],
    extraPatterns = [],
  } = {},
) {
  const boxes = [];
  const roster = compileRoster(people);
  const exceptionSet = new Set([
    ...DEFAULT_HONORIFIC_EXCEPTIONS,
    ...(Array.isArray(extraHonorificExceptions) ? extraHonorificExceptions : []),
  ]);

  const validExtraLabelRes = (Array.isArray(extraLabels) ? extraLabels : [])
    .map((lbl) => String(lbl ?? '').trim())
    .filter((lbl) => lbl.length > 0)
    .map((lbl) => new RegExp(escapeRegExp(lbl), 'gi'));

  const validExtraPatternRes = (Array.isArray(extraPatterns) ? extraPatterns : [])
    .filter((pat) => validateSafeRegexPattern(pat).ok)
    .map((pat) => new RegExp(pat, 'g'));

  for (const line of lines) {
    const text = line.text;
    if (!text) continue;

    // 1. Known people (full names and parts >= 2 chars)
    if (roster.patternSrc) {
      const normalized = normalizeWithMap(text);
      const regex = new RegExp(roster.patternSrc, 'gi');
      for (const m of normalized.text.matchAll(regex)) {
        if (!m[0]) continue;
        const start = m.index ?? 0;
        const end = start + m[0].length;
        const range = normalized.originalRange(start, end);
        const box = unionBoxes(line.boxes, range.start, range.end);
        if (box) boxes.push(box);
      }
    }

    // 2. Honorific fallback (covers unrecognized handwritten/printed names)
    for (const m of text.matchAll(HONORIFIC_RE)) {
      const rawStem = m[1];
      const suffix = m[2];
      const matchStart = m.index ?? 0;
      if (!rawStem || !suffix) continue;
      let stemOffset = 0;
      let stem = rawStem;
      while (stem.length >= 2 && LEADING_PARTICLES.has(stem[0])) {
        const rest = stem.slice(1);
        if (KANJI_OR_KATAKANA_START_RE.test(rest) || rest.length >= 2) {
          stemOffset += 1;
          stem = rest;
        } else {
          break;
        }
      }
      if (exceptionSet.has(stem) || exceptionSet.has(`${stem}${suffix}`)) {
        continue;
      }
      const nameStart = matchStart + stemOffset;
      const box = unionBoxes(line.boxes, nameStart, nameStart + stem.length);
      if (box) boxes.push(box);
    }

    // 3. Explicit PII patterns on the page (+ additive school studentIdPatterns)
    for (const re of [EMAIL_RE, PHONE_RE, POSTAL_RE]) {
      for (const m of text.matchAll(re)) {
        const start = m.index ?? 0;
        const box = unionBoxes(line.boxes, start, start + m[0].length);
        if (box) boxes.push(box);
      }
    }
    if (validExtraPatternRes.length > 0) {
      const normalized = normalizeWithMap(text);
      for (const re of validExtraPatternRes) {
        for (const m of boundedSchoolMatches(re, normalized.text)) {
          const range = normalized.originalRange(m.index, m.index + m.text.length);
          const box = unionBoxes(line.boxes, range.start, range.end);
          if (box) boxes.push(box);
        }
      }
    }

    // 4. Label rule: redact both right and below regions next to name/ID labels
    const labelSpans = [];
    for (const m of text.matchAll(LABEL_RE)) {
      const start = m.index ?? 0;
      labelSpans.push({ start, end: start + m[0].length });
    }
    if (text.trim().length <= NAME_LABEL_MAX_LINE_LENGTH) {
      const shortMatch = SHORT_LINE_NAME_LABEL_RE.exec(text);
      if (shortMatch) {
        const start = shortMatch[1].length;
        const end = start + shortMatch[2].length;
        const alreadyCovered = labelSpans.some(
          (s) => start < s.end && end > s.start,
        );
        if (!alreadyCovered) {
          labelSpans.push({ start, end });
        }
      }
    }
    for (const extraRe of validExtraLabelRes) {
      for (const m of text.matchAll(extraRe)) {
        if (!m[0]) continue;
        const start = m.index ?? 0;
        const end = start + m[0].length;
        const alreadyCovered = labelSpans.some(
          (s) => start < s.end && end > s.start,
        );
        if (!alreadyCovered) {
          labelSpans.push({ start, end });
        }
      }
    }

    for (const span of labelSpans) {
      const labelBox = unionBoxes(line.boxes, span.start, span.end);
      if (!labelBox) continue;

      const h = labelBox.height;
      // Right of the label (e.g. `氏名： [handwritten name]`)
      boxes.push({
        left: labelBox.right,
        top: labelBox.top - 0.3 * h,
        right: labelBox.right + 6 * h,
        bottom: labelBox.bottom + 0.3 * h,
      });
      // Below the label (e.g. header cell with name written underneath)
      boxes.push({
        left: labelBox.left,
        top: labelBox.bottom,
        right: labelBox.left + Math.max(labelBox.width * 2, 6 * h),
        bottom: labelBox.bottom + 2.2 * h,
      });
    }
  }

  return boxes;
}

/**
 * Computes the exact union area of possibly overlapping axis-aligned boxes
 * via x-sweep + vertical interval merge.
 */
export function computeBoxesUnionArea(boxes) {
  if (!Array.isArray(boxes) || boxes.length === 0) return 0;
  const xsSet = new Set();
  const valid = [];
  for (const b of boxes) {
    if (b && b.right > b.left && b.bottom > b.top) {
      valid.push(b);
      xsSet.add(b.left);
      xsSet.add(b.right);
    }
  }
  if (valid.length === 0) return 0;

  const xs = [...xsSet].sort((a, b) => a - b);
  let area = 0;
  for (let i = 0; i < xs.length - 1; i++) {
    const dx = xs[i + 1] - xs[i];
    if (dx <= 0) continue;
    const midX = (xs[i] + xs[i + 1]) / 2;
    const yIntervals = [];
    for (const b of valid) {
      if (b.left <= midX && midX <= b.right) {
        yIntervals.push([b.top, b.bottom]);
      }
    }
    if (yIntervals.length === 0) continue;
    yIntervals.sort((a, b) => a[0] - b[0]);
    let curTop = yIntervals[0][0];
    let curBottom = yIntervals[0][1];
    let coveredY = 0;
    for (let k = 1; k < yIntervals.length; k++) {
      const [t, bot] = yIntervals[k];
      if (t <= curBottom) {
        if (bot > curBottom) curBottom = bot;
      } else {
        coveredY += curBottom - curTop;
        curTop = t;
        curBottom = bot;
      }
    }
    coveredY += curBottom - curTop;
    area += dx * coveredY;
  }
  return area;
}

export function expandAndClampBoxes(
  boxes,
  imgWidth,
  imgHeight,
  expandRatio = REDACTION_EXPAND_RATIO,
) {
  const out = [];
  for (const box of boxes) {
    const w = box.right - box.left;
    const h = box.bottom - box.top;
    if (w <= 0 || h <= 0) continue;
    const padX = w * expandRatio;
    const padY = h * expandRatio;
    const left = Math.max(0, Math.floor(box.left - padX));
    const top = Math.max(0, Math.floor(box.top - padY));
    const right = Math.min(imgWidth, Math.ceil(box.right + padX));
    const bottom = Math.min(imgHeight, Math.ceil(box.bottom + padY));
    if (right > left && bottom > top) {
      out.push({
        left,
        top,
        right,
        bottom,
        width: right - left,
        height: bottom - top,
      });
    }
  }
  return out;
}

/**
 * Normalizes an image exactly like [redactImageForAi] (EXIF auto-orient,
 * longest edge <= 2048px, metadata stripped) and returns Cloud Vision
 * `DOCUMENT_TEXT_DETECTION` output for it. Used by timetable import to
 * rebuild a grid from coordinates — the image itself is never sent to Gemini.
 *
 * Fail-closed: sharp/Vision failures throw `HttpsError('unavailable')`.
 * Never logs OCR text — only `{ mimeType, latencyMs }`.
 */
export async function ocrImageDocument(
  buffer,
  mimeType,
  { visionClient = getVisionClient(), timeoutMs = VISION_TIMEOUT_MS } = {},
) {
  const formatSpec = sharpFormatForMime(mimeType);
  if (!formatSpec) {
    throw new HttpsError('invalid-argument', 'Unsupported image type.');
  }
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw new HttpsError('invalid-argument', 'ファイルの読み取りに失敗しました。');
  }
  const startedAt = Date.now();
  try {
    const { data: orientedBuffer, info } = await sharp(buffer)
      .rotate()
      .resize({
        width: IMAGE_REDACT_MAX_EDGE,
        height: IMAGE_REDACT_MAX_EDGE,
        fit: 'inside',
        withoutEnlargement: true,
      })
      .toFormat(formatSpec.format, formatSpec.options)
      .toBuffer({ resolveWithObject: true });
    const [ocrResponse] = await withTimeout(
      visionClient.documentTextDetection({
        image: { content: orientedBuffer },
        imageContext: { languageHints: ['ja', 'en'] },
      }),
      timeoutMs,
      'Vision OCR',
    );
    if (ocrResponse?.error) {
      throw new Error(`Vision OCR error code ${ocrResponse.error.code ?? 'UNKNOWN'}`);
    }
    logger.info('Image OCR completed', { mimeType, latencyMs: Date.now() - startedAt });
    return {
      width: info.width,
      height: info.height,
      fullTextAnnotation: ocrResponse?.fullTextAnnotation ?? null,
    };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error('Image OCR failed (fail-closed)', {
      mimeType,
      errorType: err?.name ?? err?.code ?? 'OCR_ERROR',
      latencyMs: Date.now() - startedAt,
    });
    throw new HttpsError(
      'unavailable',
      '画像の文字認識に失敗しました。しばらくしてからもう一度お試しください。',
      { reason: ERROR_REASONS.ocrFailed },
    );
  }
}

/**
 * Normalizes EXIF orientation + max dimension, runs Cloud Vision OCR, and
 * composites opaque black boxes over detected PII/names/labels.
 *
 * Fail-closed: any failure in `sharp` or Vision throws `HttpsError('unavailable')`
 * so the unredacted image never reaches Gemini.
 * Never logs OCR text, names, or coordinates — only `{ mimeType, redactedBoxCount, latencyMs }`.
 */
export async function redactImageForAi(
  buffer,
  mimeType,
  people,
  {
    visionClient = getVisionClient(),
    timeoutMs = VISION_TIMEOUT_MS,
    extraLabels = [],
    extraHonorificExceptions = [],
    extraPatterns = [],
  } = {},
) {
  const formatSpec = sharpFormatForMime(mimeType);
  if (!formatSpec) {
    throw new HttpsError('invalid-argument', 'Unsupported image type.');
  }
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw new HttpsError('invalid-argument', 'ファイルの読み取りに失敗しました。');
  }

  const startedAt = Date.now();
  try {
    // Step a + b: Auto-orient from EXIF, cap longest edge to 2048px, strip metadata.
    const { data: orientedBuffer, info } = await sharp(buffer)
      .rotate()
      .resize({
        width: IMAGE_REDACT_MAX_EDGE,
        height: IMAGE_REDACT_MAX_EDGE,
        fit: 'inside',
        withoutEnlargement: true,
      })
      .toFormat(formatSpec.format, formatSpec.options)
      .toBuffer({ resolveWithObject: true });

    const width = info.width;
    const height = info.height;
    if (!width || !height) {
      throw new Error('Invalid image dimensions after normalization');
    }

    // Step c: Cloud Vision DOCUMENT_TEXT_DETECTION on the EXACT oriented buffer.
    const [ocrResponse] = await withTimeout(
      visionClient.documentTextDetection({
        image: { content: orientedBuffer },
        imageContext: { languageHints: ['ja', 'en'] },
      }),
      timeoutMs,
      'Vision OCR',
    );
    if (ocrResponse?.error) {
      throw new Error(`Vision OCR error code ${ocrResponse.error.code ?? 'UNKNOWN'}`);
    }

    const lines = extractOcrLines(ocrResponse?.fullTextAnnotation);
    const rawBoxes = findRedactionBoxes(lines, people, {
      extraLabels,
      extraHonorificExceptions,
      extraPatterns,
    });
    const clampedBoxes = expandAndClampBoxes(rawBoxes, width, height);
    const imageArea = width * height;
    const redactedArea = computeBoxesUnionArea(clampedBoxes);
    const redactionAreaRatio = imageArea > 0 ? redactedArea / imageArea : 0;
    const highRedactionWarning =
      redactionAreaRatio > HIGH_REDACTION_AREA_THRESHOLD;

    let outputBuffer = orientedBuffer;
    if (clampedBoxes.length > 0) {
      const rects = clampedBoxes
        .map(
          (b) =>
            `<rect x="${b.left}" y="${b.top}" width="${b.width}" height="${b.height}" fill="#000000"/>`,
        )
        .join('');
      const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${rects}</svg>`;
      outputBuffer = await sharp(orientedBuffer)
        .composite([{ input: Buffer.from(svg), top: 0, left: 0 }])
        .toFormat(formatSpec.format, formatSpec.options)
        .toBuffer();
    }

    logger.info('Image redaction completed', {
      mimeType,
      redactedBoxCount: clampedBoxes.length,
      highRedactionWarning,
      latencyMs: Date.now() - startedAt,
    });

    return {
      buffer: outputBuffer,
      width,
      height,
      redactedBoxCount: clampedBoxes.length,
      boxes: clampedBoxes,
      redactionAreaRatio,
      highRedactionWarning,
    };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error('Image redaction failed (fail-closed)', {
      mimeType,
      errorType: err?.name ?? err?.code ?? 'REDACTION_ERROR',
      latencyMs: Date.now() - startedAt,
    });
    throw new HttpsError(
      'unavailable',
      '画像のプライバシー保護処理に失敗しました。しばらくしてからもう一度お試しください。',
    );
  }
}
