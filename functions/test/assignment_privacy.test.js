import { test } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { setGeminiGenerateContentForTest } from '../ai/gemini_provider.js';
import {
  redactImageForAi,
  setVisionClientForTest,
} from '../privacy/image_redactor.js';
import {
  MAX_PDF_PAGES,
  SCANNED_PDF_ERROR_CODE,
  extractPdfText,
} from '../privacy/pdf_extractor.js';
import { buildJapaneseCidPdfBuffer } from './fixtures/japanese_cid_pdf.js';
import { analyzeAssignmentSubmission } from '../index.js';

// ---------------------------------------------------------------------------
// In-memory Firestore harness
// ---------------------------------------------------------------------------
const isPlain = (v) => v && Object.getPrototypeOf(v) === Object.prototype;
const cloneData = (v) => {
  if (Array.isArray(v)) return v.map(cloneData);
  if (isPlain(v)) {
    const out = {};
    for (const [k, val] of Object.entries(v)) out[k] = cloneData(val);
    return out;
  }
  return v;
};

const store = new Map();
const db = getFirestore();
logger.error = () => {};
logger.warn = () => {};
logger.info = () => {};

function setupDbHarness() {
  db.collection = (col) => ({
    doc: (id) => {
      const path = `${col}/${id}`;
      return {
        id,
        path,
        ref: { id, path },
        get: async () => {
          const d = store.get(path);
          return {
            exists: d !== undefined,
            id,
            ref: { id, path },
            data: () => (d ? cloneData(d) : undefined),
          };
        },
        set: async (data, opts) => {
          if (opts?.merge && store.has(path)) {
            store.set(path, { ...store.get(path), ...data });
          } else {
            store.set(path, cloneData(data));
          }
        },
        update: async (fields) => {
          const cur = store.get(path) ?? {};
          store.set(path, { ...cur, ...fields });
        },
      };
    },
    where: (field, op, val) => ({
      limit: () => ({
        get: async () => {
          const docs = [];
          for (const [path, d] of store.entries()) {
            if (!path.startsWith(`${col}/`)) continue;
            let match = false;
            if (op === '==' && d[field] === val) match = true;
            if (op === 'array-contains' && Array.isArray(d[field]) && d[field].includes(val)) match = true;
            if (match) {
              const id = path.slice(col.length + 1);
              docs.push({ id, ref: { id, path }, data: () => cloneData(d) });
            }
          }
          return { empty: docs.length === 0, docs, size: docs.length };
        },
      }),
    }),
  });

  db.getAll = async (...refs) =>
    refs.map((ref) => {
      const d = store.get(ref.path);
      return {
        exists: d !== undefined,
        id: ref.id,
        ref,
        data: () => (d ? cloneData(d) : undefined),
      };
    });

  db.runTransaction = async (callback) => {
    const tx = {
      get: async (ref) => {
        const d = store.get(ref.path);
        return {
          exists: d !== undefined,
          id: ref.id,
          ref,
          data: () => (d ? cloneData(d) : undefined),
        };
      },
      set: (ref, data, opts) => {
        if (opts?.merge && store.has(ref.path)) {
          store.set(ref.path, { ...store.get(ref.path), ...data });
        } else {
          store.set(ref.path, cloneData(data));
        }
      },
      update: (ref, data) => {
        const cur = store.get(ref.path) ?? {};
        store.set(ref.path, { ...cur, ...data });
      },
    };
    return await callback(tx);
  };
}

function resetHarness() {
  setupDbHarness();
  store.clear();
  setGeminiGenerateContentForTest(null);
  setVisionClientForTest(null);
  store.set('users/u_stu', { name: '山田太郎' });
  store.set('timetables/tt_1', { userId: 'u_stu', teacher: '高橋誠', subject: '数学' });
}

const callerAuth = {
  uid: 'u_stu',
  token: { email: 'taro@gmail.com', email_verified: true },
};

// ---------------------------------------------------------------------------
// Image & PDF Helpers
// ---------------------------------------------------------------------------
async function createTestPng({ width = 400, height = 300, bg = '#FFFFFF' } = {}) {
  return sharp({
    create: { width, height, channels: 3, background: bg },
  })
    .png()
    .toBuffer();
}

async function readPixelRgb(buffer, x, y) {
  const { data, info } = await sharp(buffer)
    .raw()
    .toBuffer({ resolveWithObject: true });
  const idx = (y * info.width + x) * info.channels;
  return [data[idx], data[idx + 1], data[idx + 2]];
}

function makeWord(text, left, top, right, bottom, breakType = null) {
  const step = (right - left) / Math.max(1, text.length);
  const symbols = [...text].map((ch, idx) => {
    const sLeft = Math.round(left + idx * step);
    const sRight = Math.round(left + (idx + 1) * step);
    const sym = {
      text: ch,
      boundingBox: {
        vertices: [
          { x: sLeft, y: top },
          { x: sRight, y: top },
          { x: sRight, y: bottom },
          { x: sLeft, y: bottom },
        ],
      },
    };
    if (idx === text.length - 1 && breakType) {
      sym.property = { detectedBreak: { type: breakType } };
    }
    return sym;
  });
  return { symbols };
}

function buildVisionAnnotation(paragraphs) {
  return {
    fullTextAnnotation: {
      pages: [
        {
          blocks: [
            {
              paragraphs: paragraphs.map((words) => ({ words })),
            },
          ],
        },
      ],
    },
  };
}

function buildMinimalPdfBuffer(textLines) {
  const streamOps = textLines
    .map((line, i) => `BT /F1 12 Tf 10 ${180 - i * 16} Td (${line}) Tj ET`)
    .join('\n');
  const objects = [
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
    `4 0 obj << /Length ${Buffer.byteLength(streamOps, 'utf8')} >> stream\n${streamOps}\nendstream endobj\n`,
    '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  for (const obj of objects) {
    offsets.push(Buffer.byteLength(pdf, 'utf8'));
    pdf += obj;
  }
  const xrefOffset = Buffer.byteLength(pdf, 'utf8');
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (let i = 1; i <= objects.length; i++) {
    pdf += `${String(offsets[i]).padStart(10, '0')} 00000 n \n`;
  }
  pdf += `trailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;
  return Buffer.from(pdf, 'utf8');
}

// ---------------------------------------------------------------------------
// Stage 3 Tests
// ---------------------------------------------------------------------------

test('Image with printed student name is blacked out before reaching Gemini', async () => {
  resetHarness();
  const originalPng = await createTestPng({ width: 400, height: 300 });

  setVisionClientForTest({
    documentTextDetection: async () => [
      buildVisionAnnotation([
        [makeWord('山田太郎', 40, 30, 160, 60, 'EOL_SURE_SPACE')],
        [makeWord('x + 2 = 5', 40, 120, 180, 150, 'EOL_SURE_SPACE')],
      ]),
    ],
  });

  let sentInlineData = null;
  setGeminiGenerateContentForTest(async (cfg) => {
    sentInlineData = cfg.contents[0].parts[1].inlineData;
    return {
      text: JSON.stringify({
        completionPercent: 90,
        missingParts: ['[TEACHER_1]先生の検算'],
        advice: '[STUDENT_1]さん、よくできています。',
      }),
    };
  });

  const res = await analyzeAssignmentSubmission.run({
    auth: callerAuth,
    data: {
      subject: '数学',
      title: '山田太郎の課題',
      description: '高橋誠先生の課題',
      fileBase64: originalPng.toString('base64'),
      mimeType: 'image/png',
      language: 'ja',
    },
  });

  assert.equal(res.completionPercent, 90);
  assert.deepEqual(res.missingParts, ['高橋誠先生の検算']);
  assert.equal(res.advice, '山田太郎さん、よくできています。');

  assert.ok(sentInlineData);
  const sentBuf = Buffer.from(sentInlineData.data, 'base64');
  assert.notEqual(Buffer.compare(sentBuf, originalPng), 0);

  // Inside the name box (40..160, 30..60) -> black
  assert.deepEqual(await readPixelRgb(sentBuf, 100, 45), [0, 0, 0]);
  // Outside (math formula area) -> still white
  assert.deepEqual(await readPixelRgb(sentBuf, 100, 135), [255, 255, 255]);
});

test('Image with 氏名 label blacks out both right and below regions even when handwriting is unrecognized', async () => {
  resetHarness();
  const originalPng = await createTestPng({ width: 500, height: 300 });

  setVisionClientForTest({
    documentTextDetection: async () => [
      buildVisionAnnotation([
        // Only the printed label "氏名" was detected by OCR; the handwritten
        // name next to/below it was missed.
        [makeWord('氏名', 40, 40, 90, 70, 'EOL_SURE_SPACE')],
      ]),
    ],
  });

  let sentInlineData = null;
  setGeminiGenerateContentForTest(async (cfg) => {
    sentInlineData = cfg.contents[0].parts[1].inlineData;
    return {
      text: JSON.stringify({ completionPercent: 70, missingParts: [], advice: 'OK' }),
    };
  });

  await analyzeAssignmentSubmission.run({
    auth: callerAuth,
    data: {
      subject: '英語',
      fileBase64: originalPng.toString('base64'),
      mimeType: 'image/png',
      language: 'ja',
    },
  });

  const sentBuf = Buffer.from(sentInlineData.data, 'base64');
  // Label height h = 30.
  // Right region: x in [90, 90 + 180 = 270], y in [31, 79] (+20% padding)
  assert.deepEqual(await readPixelRgb(sentBuf, 180, 55), [0, 0, 0]);
  // Below region: x in [40, 40 + 180 = 220], y in [70, 70 + 66 = 136] (+20% padding)
  assert.deepEqual(await readPixelRgb(sentBuf, 120, 105), [0, 0, 0]);
  // Far corner remains white
  assert.deepEqual(await readPixelRgb(sentBuf, 450, 260), [255, 255, 255]);
});

test('90-degree EXIF-rotated image is normalized first so redaction lands on post-rotation coordinates and strips EXIF', async () => {
  resetHarness();
  // Create a 400x200 landscape JPEG tagged with EXIF orientation 6 (90° CW),
  // which represents a 200x400 portrait image after orientation normalization.
  const rotatedJpeg = await sharp({
    create: { width: 400, height: 200, channels: 3, background: '#FFFFFF' },
  })
    .withMetadata({ orientation: 6 })
    .jpeg()
    .toBuffer();

  const rawMeta = await sharp(rotatedJpeg).metadata();
  assert.equal(rawMeta.orientation, 6);
  assert.equal(rawMeta.width, 400);
  assert.equal(rawMeta.height, 200);

  let ocrImageMeta = null;
  setVisionClientForTest({
    documentTextDetection: async ({ image }) => {
      ocrImageMeta = await sharp(image.content).metadata();
      // Name appears near bottom of the upright 200x400 portrait image
      return [
        buildVisionAnnotation([
          [makeWord('山田太郎', 30, 320, 150, 355, 'EOL_SURE_SPACE')],
        ]),
      ];
    },
  });

  let sentInlineData = null;
  setGeminiGenerateContentForTest(async (cfg) => {
    sentInlineData = cfg.contents[0].parts[1].inlineData;
    return {
      text: JSON.stringify({ completionPercent: 100, missingParts: [], advice: 'Good' }),
    };
  });

  await analyzeAssignmentSubmission.run({
    auth: callerAuth,
    data: {
      subject: '化学',
      fileBase64: rotatedJpeg.toString('base64'),
      mimeType: 'image/jpeg',
      language: 'ja',
    },
  });

  // OCR must have seen upright 200x400 with EXIF orientation stripped
  assert.equal(ocrImageMeta.width, 200);
  assert.equal(ocrImageMeta.height, 400);
  assert.equal(ocrImageMeta.orientation, undefined);

  const sentBuf = Buffer.from(sentInlineData.data, 'base64');
  const sentMeta = await sharp(sentBuf).metadata();
  assert.equal(sentMeta.width, 200);
  assert.equal(sentMeta.height, 400);
  assert.equal(sentMeta.orientation, undefined);

  // Redacted pixel at upright coordinates (90, 338) must be near black (JPEG compression tolerance <= 10)
  const [r, g, b] = await readPixelRgb(sentBuf, 90, 338);
  assert.ok(r <= 10 && g <= 10 && b <= 10, `Expected black pixel, got [${r},${g},${b}]`);
  // Unredacted area near top (90, 40) stays white
  const [wr, wg, wb] = await readPixelRgb(sentBuf, 90, 40);
  assert.ok(wr >= 245 && wg >= 245 && wb >= 245, `Expected white pixel, got [${wr},${wg},${wb}]`);
});

test('Image with no names passes through without black boxes and resizes > 2048px', async () => {
  resetHarness();
  const largePng = await createTestPng({ width: 2600, height: 1300 });

  let ocrMeta = null;
  const result = await redactImageForAi(largePng, 'image/png', [{ id: '1', fullName: '山田太郎', role: 'student' }], {
    visionClient: {
      documentTextDetection: async ({ image }) => {
        ocrMeta = await sharp(image.content).metadata();
        return [
          buildVisionAnnotation([
            [makeWord('2 + 2 = 4', 100, 100, 300, 140, 'EOL_SURE_SPACE')],
          ]),
        ];
      },
    },
  });

  assert.equal(ocrMeta.width, 2048);
  assert.equal(ocrMeta.height, 1024);
  assert.equal(result.width, 2048);
  assert.equal(result.height, 1024);
  assert.equal(result.redactedBoxCount, 0);
  assert.deepEqual(await readPixelRgb(result.buffer, 200, 120), [255, 255, 255]);
});

test('Vision API error is fail-closed: Gemini is never called and quota is refunded', async () => {
  resetHarness();
  const png = await createTestPng();
  let geminiCalled = false;

  setVisionClientForTest({
    documentTextDetection: async () => {
      throw new Error('Vision quota exceeded');
    },
  });
  setGeminiGenerateContentForTest(async () => {
    geminiCalled = true;
    return { text: '{}' };
  });

  await assert.rejects(
    () =>
      analyzeAssignmentSubmission.run({
        auth: callerAuth,
        data: {
          subject: '数学',
          fileBase64: png.toString('base64'),
          mimeType: 'image/png',
          language: 'ja',
        },
      }),
    (err) => err.code === 'unavailable',
  );

  assert.equal(geminiCalled, false, 'Gemini must NEVER be called when Vision fails');
  const usage = store.get('ai_usage/u_stu');
  assert.equal(usage?.count ?? 0, 0, 'Quota must be refunded on fail-closed redaction error');
});

test('Vision API timeout is fail-closed', async () => {
  resetHarness();
  const png = await createTestPng();

  await assert.rejects(
    () =>
      redactImageForAi(png, 'image/png', [], {
        timeoutMs: 25,
        visionClient: {
          documentTextDetection: () => new Promise(() => {}),
        },
      }),
    (err) => err.code === 'unavailable',
  );
});

test('HEIC/HEIF images are explicitly rejected without calling Gemini', async () => {
  resetHarness();
  let geminiCalled = false;
  setGeminiGenerateContentForTest(async () => {
    geminiCalled = true;
    return { text: '{}' };
  });

  await assert.rejects(
    () =>
      analyzeAssignmentSubmission.run({
        auth: callerAuth,
        data: {
          subject: '英語',
          fileBase64: Buffer.from('fake-heic').toString('base64'),
          mimeType: 'image/heic',
          language: 'ja',
        },
      }),
    (err) => err.code === 'invalid-argument' && err.details?.reason === 'unsupported_heic',
  );
  assert.equal(geminiCalled, false);
});

test('Text PDF extracts text, masks names/PII, sends NO inlineData, and restores tokens', async () => {
  resetHarness();
  // ASCII text with known Latin name & phone/email + Japanese name registered in roster
  store.set('users/u_stu', { name: 'Taro Yamada' });
  const pdfBuf = buildMinimalPdfBuffer([
    'Student: Taro Yamada',
    'Email: taro@gmail.com',
    'Homework essay: Photosynthesis converts light energy into chemical energy.',
  ]);

  let capturedContents = null;
  setGeminiGenerateContentForTest(async (cfg) => {
    capturedContents = cfg.contents;
    return {
      text: JSON.stringify({
        completionPercent: 85,
        missingParts: ['Add diagram by [STUDENT_1]'],
        advice: 'Nice work [STUDENT_1], contact [EMAIL_1] is hidden.',
      }),
    };
  });

  const res = await analyzeAssignmentSubmission.run({
    auth: callerAuth,
    data: {
      subject: 'Biology',
      title: 'Taro Yamada report',
      fileBase64: pdfBuf.toString('base64'),
      mimeType: 'application/pdf',
      language: 'en',
    },
  });

  assert.equal(res.completionPercent, 85);
  assert.deepEqual(res.missingParts, ['Add diagram by Taro Yamada']);
  assert.equal(res.advice, 'Nice work Taro Yamada, contact taro@gmail.com is hidden.');

  // Verify NO inlineData was sent to Gemini and NO real PII appeared in text
  const parts = capturedContents[0].parts;
  assert.equal(parts.every((p) => !p.inlineData), true, 'PDF must never be sent as inlineData');
  const sentJson = JSON.stringify(capturedContents);
  assert.ok(!sentJson.includes('Taro Yamada'));
  assert.ok(!sentJson.includes('taro@gmail.com'));
  assert.ok(sentJson.includes('[STUDENT_1]'));
  assert.ok(sentJson.includes('[EMAIL_1]'));
});

test('Scanned PDF (< 50 chars/page) is rejected without calling Gemini and refunds quota', async () => {
  resetHarness();
  const scannedPdf = buildMinimalPdfBuffer(['1']); // Only 1 char on 1 page -> < 50
  let geminiCalled = false;

  setGeminiGenerateContentForTest(async () => {
    geminiCalled = true;
    return { text: '{}' };
  });

  await assert.rejects(
    () =>
      analyzeAssignmentSubmission.run({
        auth: callerAuth,
        data: {
          subject: '数学',
          fileBase64: scannedPdf.toString('base64'),
          mimeType: 'application/pdf',
          language: 'ja',
        },
      }),
    (err) =>
      err.code === 'invalid-argument' &&
      err.details?.reason === 'scanned_pdf' &&
      err.details?.code === SCANNED_PDF_ERROR_CODE,
  );

  assert.equal(geminiCalled, false);
  const usage = store.get('ai_usage/u_stu');
  assert.equal(usage?.count ?? 0, 0, 'Quota must be refunded for scanned PDF rejection');
});

test('Japanese MS-Mincho/YuMincho CID-font PDF requires CMap, extracts text, masks names, and is not marked scanned', async () => {
  resetHarness();
  const cidPdf = buildJapaneseCidPdfBuffer();

  // Without CMap, Japanese CID text cannot be decoded -> misclassified as scanned
  await assert.rejects(
    () => extractPdfText(cidPdf, { useCmaps: false }),
    (err) => err.code === 'invalid-argument' && err.details?.reason === 'scanned_pdf',
  );

  // With default CMap configuration, all Japanese text extracts cleanly
  const extracted = await extractPdfText(cidPdf);
  assert.ok(extracted.text.includes('山田太郎'));
  assert.ok(extracted.text.includes('高橋誠'));
  assert.ok(extracted.avgCharsPerPage >= 50);

  let capturedPromptText = '';
  let sentInlineData = false;
  setGeminiGenerateContentForTest(async (cfg) => {
    const parts = cfg.contents[0].parts;
    sentInlineData = parts.some((p) => Boolean(p.inlineData));
    capturedPromptText = parts.map((p) => p.text ?? '').join('\n');
    return {
      text: JSON.stringify({
        completionPercent: 95,
        missingParts: ['[TEACHER_1]先生への確認'],
        advice: '[STUDENT_1]さんの解答は正確です。',
      }),
    };
  });

  const res = await analyzeAssignmentSubmission.run({
    auth: callerAuth,
    data: {
      subject: '数学',
      title: '二次関数課題',
      fileBase64: cidPdf.toString('base64'),
      mimeType: 'application/pdf',
      language: 'ja',
    },
  });

  assert.equal(sentInlineData, false);
  assert.ok(!capturedPromptText.includes('山田太郎'));
  assert.ok(!capturedPromptText.includes('高橋誠'));
  assert.ok(capturedPromptText.includes('[STUDENT_1]'));
  assert.ok(capturedPromptText.includes('[TEACHER_1]'));
  assert.deepEqual(res.missingParts, ['高橋誠先生への確認']);
  assert.equal(res.advice, '山田太郎さんの解答は正確です。');
  assert.equal(res.highRedactionWarning, false);
});

test('PDF extractor caps pages read at MAX_PDF_PAGES (30) and enforces timeout', async () => {
  const multiPagePdf = buildJapaneseCidPdfBuffer({ pageCount: 35 });
  const extracted = await extractPdfText(multiPagePdf);
  assert.equal(extracted.numPages, 35);
  assert.equal(extracted.pagesRead, MAX_PDF_PAGES);

  await assert.rejects(
    () => extractPdfText(multiPagePdf, { timeoutMs: 1 }),
    (err) => err.code === 'invalid-argument',
  );
});

test('Label rule does NOT redact standalone 番号 or "Name the following", while redacting Name:, short Name, 学籍番号, and 出席番号', async () => {
  resetHarness();
  const png = await createTestPng({ width: 500, height: 300 });

  // Non-identity phrases that must NOT be redacted
  const safeResult = await redactImageForAi(png, 'image/png', [], {
    visionClient: {
      documentTextDetection: async () => [
        buildVisionAnnotation([
          [makeWord('番号で答えなさい', 40, 40, 220, 70, 'EOL_SURE_SPACE')],
          [
            makeWord('Name', 40, 100, 100, 130, 'SPACE'),
            makeWord('the', 108, 100, 145, 130, 'SPACE'),
            makeWord('following', 153, 100, 260, 130, 'EOL_SURE_SPACE'),
          ],
        ]),
      ],
    },
  });
  assert.equal(safeResult.redactedBoxCount, 0);
  assert.equal(safeResult.highRedactionWarning, false);

  // Actual identity labels that MUST be redacted
  const labelResult = await redactImageForAi(png, 'image/png', [], {
    visionClient: {
      documentTextDetection: async () => [
        buildVisionAnnotation([
          [makeWord('Name:', 40, 20, 100, 45, 'EOL_SURE_SPACE')],
          [makeWord('Name', 40, 90, 95, 115, 'EOL_SURE_SPACE')],
          [makeWord('学籍番号', 40, 160, 120, 185, 'EOL_SURE_SPACE')],
          [makeWord('出席番号', 40, 230, 120, 255, 'EOL_SURE_SPACE')],
        ]),
      ],
    },
  });
  assert.equal(labelResult.redactedBoxCount, 8);
});

test('Redaction covering > 30% of image returns highRedactionWarning=true without blocking Gemini', async () => {
  resetHarness();
  const smallPng = await createTestPng({ width: 200, height: 200 });

  setVisionClientForTest({
    documentTextDetection: async () => [
      buildVisionAnnotation([
        // Large name box covering ~150x100 = 15,000 px (> 37.5% of 40,000 px)
        [makeWord('山田太郎', 20, 30, 170, 130, 'EOL_SURE_SPACE')],
      ]),
    ],
  });

  let geminiCalled = false;
  setGeminiGenerateContentForTest(async () => {
    geminiCalled = true;
    return {
      text: JSON.stringify({
        completionPercent: 60,
        missingParts: ['一部が黒塗りされています'],
        advice: '確認しました。',
      }),
    };
  });

  const res = await analyzeAssignmentSubmission.run({
    auth: callerAuth,
    data: {
      subject: '数学',
      fileBase64: smallPng.toString('base64'),
      mimeType: 'image/png',
      language: 'ja',
    },
  });

  assert.equal(geminiCalled, true);
  assert.equal(res.highRedactionWarning, true);
  assert.equal(res.completionPercent, 60);
});
