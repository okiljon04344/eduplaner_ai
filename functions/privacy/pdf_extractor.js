import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { HttpsError } from 'firebase-functions/https';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { ERROR_REASONS } from '../shared/error_reasons.js';

export const MIN_PDF_CHARS_PER_PAGE = 50;
export const MAX_PDF_PAGES = 30;
export const PDF_EXTRACT_TIMEOUT_MS = 15_000;
export const SCANNED_PDF_ERROR_CODE = 'SCANNED_PDF_NOT_SUPPORTED';

function ensureTrailingSep(dirPath) {
  return dirPath.endsWith(path.sep) ? dirPath : `${dirPath}${path.sep}`;
}

export const PDFJS_CMAP_URL = ensureTrailingSep(
  fileURLToPath(new URL('../node_modules/pdfjs-dist/cmaps/', import.meta.url)),
);

export const PDFJS_STANDARD_FONT_DATA_URL = ensureTrailingSep(
  fileURLToPath(
    new URL('../node_modules/pdfjs-dist/standard_fonts/', import.meta.url),
  ),
);

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

/**
 * Extracts UTF-8 text page-by-page (up to [MAX_PDF_PAGES]) from a PDF buffer
 * using `pdfjs-dist` configured with CMap & standard font data for Japanese
 * CID fonts (`MS明朝`, `游明朝`, etc.), `isEvalSupported: false`, and
 * `disableFontFace: true`.
 *
 * If the average extracted character count per read page is below
 * [MIN_PDF_CHARS_PER_PAGE] (50), the PDF is treated as a scanned/image PDF
 * and rejected with an `invalid-argument` [HttpsError] carrying
 * `details: { reason: 'scanned_pdf' }` so Gemini is never called with raw
 * unredacted PDF bytes.
 */
export async function extractPdfText(
  buffer,
  {
    maxChars = 6000,
    maxPages = MAX_PDF_PAGES,
    timeoutMs = PDF_EXTRACT_TIMEOUT_MS,
    useCmaps = true,
    includeItems = false,
  } = {},
) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw new HttpsError('invalid-argument', 'ファイルの読み取りに失敗しました。');
  }

  let loadingTask = null;
  let doc = null;
  let numPages = 0;
  let pagesRead = 0;
  const pageTexts = [];
  const pageItems = [];

  const runExtraction = async () => {
    const docOptions = {
      data: new Uint8Array(buffer),
      verbosity: 0,
      useWorkerFetch: false,
      isEvalSupported: false,
      disableFontFace: true,
      ...(useCmaps
        ? {
            cMapUrl: PDFJS_CMAP_URL,
            cMapPacked: true,
            standardFontDataUrl: PDFJS_STANDARD_FONT_DATA_URL,
          }
        : {}),
    };

    loadingTask = getDocument(docOptions);
    doc = await loadingTask.promise;
    numPages = doc.numPages || 0;
    pagesRead = Math.min(numPages, maxPages);

    for (let pageNum = 1; pageNum <= pagesRead; pageNum++) {
      const page = await doc.getPage(pageNum);
      const content = await page.getTextContent();
      let pageStr = '';
      const items = [];
      for (const item of content.items ?? []) {
        if (typeof item?.str !== 'string') continue;
        pageStr += item.str;
        pageStr += item.hasEOL ? '\n' : ' ';
        if (includeItems && item.str.trim() && Array.isArray(item.transform)) {
          const x = Number(item.transform[4]) || 0;
          const y = Number(item.transform[5]) || 0;
          const h = Math.abs(Number(item.height) || Number(item.transform[3]) || 10);
          const w = Math.abs(Number(item.width) || h * item.str.length * 0.5);
          // PDF space is y-up; convert to y-down so callers can treat it like OCR boxes.
          items.push({ text: item.str, left: x, right: x + w, top: -(y + h), bottom: -y });
        }
      }
      pageTexts.push(pageStr.trim());
      if (includeItems) pageItems.push(items);
    }
  };

  try {
    await withTimeout(runExtraction(), timeoutMs, 'PDF extraction');
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('invalid-argument', 'ファイルの読み取りに失敗しました。');
  } finally {
    if (doc && typeof doc.cleanup === 'function') {
      await doc.cleanup().catch(() => {});
    }
    if (loadingTask && typeof loadingTask.destroy === 'function') {
      await loadingTask.destroy().catch(() => {});
    }
  }

  const combined = pageTexts.filter(Boolean).join('\n\n');
  const normalizedLength = combined.replace(/\s+/g, ' ').trim().length;
  const avgCharsPerPage = pagesRead > 0 ? normalizedLength / pagesRead : 0;

  if (numPages === 0 || avgCharsPerPage < MIN_PDF_CHARS_PER_PAGE) {
    throw new HttpsError(
      'invalid-argument',
      'スキャンされたPDFは対応していません。JPGまたはPNG画像としてアップロードしてください。',
      { reason: ERROR_REASONS.scannedPdf, code: SCANNED_PDF_ERROR_CODE },
    );
  }

  return {
    text: combined.slice(0, maxChars),
    numPages,
    pagesRead,
    avgCharsPerPage,
    ...(includeItems ? { pageItems } : {}),
  };
}
