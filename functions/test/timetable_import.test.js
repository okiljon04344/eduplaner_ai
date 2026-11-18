import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ExcelJS from 'exceljs';
import sharp from 'sharp';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import {
  BATCH_CHUNK_SIZE,
  DEFAULT_IMPORT_PERIODS,
  MAX_IMPORT_FILE_BYTES,
  MAX_IMPORT_ROWS,
  MAX_IMPORT_SHEETS,
  MAX_IMPORT_XLSX_UNCOMPRESSED_BYTES,
  confirmTimetableImport as runConfirmTimetableImport,
  checkShiftJisSupport,
  decodeCsvBuffer,
  previewTimetableImport as runPreviewTimetableImport,
  resolveSchoolPeriods,
  revertTimetableImport as runRevertTimetableImport,
  setShiftJisSupportForTest,
  validateXlsxZip,
} from '../school/timetable_import.js';
import {
  confirmTimetableImport,
  previewTimetableImport,
  revertTimetableImport,
  setSchoolPolicy,
} from '../index.js';
import { dayDocId } from '../school/timetable_xlsx.js';
import { setVisionClientForTest } from '../privacy/image_redactor.js';
import { setGeminiGenerateContentForTest } from '../ai/gemini_provider.js';

// ---------------------------------------------------------------------------
// In-memory Firestore & Messaging harness
// ---------------------------------------------------------------------------
const isPlain = (v) => v && Object.getPrototypeOf(v) === Object.prototype;
const cloneData = (v) => {
  if (Array.isArray(v)) return v.map(cloneData);
  if (v instanceof Date) return new Date(v.getTime());
  if (isPlain(v)) {
    const out = {};
    for (const [k, val] of Object.entries(v)) out[k] = cloneData(val);
    return out;
  }
  return v;
};

const store = new Map();
const batchCommits = [];
const capturedLogs = [];
const sentMulticasts = [];

const db = getFirestore();
const messaging = getMessaging();

const origLogger = {
  info: logger.info,
  warn: logger.warn,
  error: logger.error,
};

function installLogSpy() {
  logger.info = (msg, meta) => capturedLogs.push({ level: 'info', msg, meta: cloneData(meta) });
  logger.warn = (msg, meta) => capturedLogs.push({ level: 'warn', msg, meta: cloneData(meta) });
  logger.error = (msg, meta) => capturedLogs.push({ level: 'error', msg, meta: cloneData(meta) });
}

function makeDocRef(col, id) {
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
        store.set(path, { ...store.get(path), ...cloneData(data) });
      } else {
        store.set(path, cloneData(data));
      }
    },
    update: async (fields) => {
      const cur = store.get(path) ?? {};
      store.set(path, { ...cur, ...cloneData(fields) });
    },
    delete: async () => {
      store.delete(path);
    },
  };
}

function makeQuery(col, filters = []) {
  return {
    where: (field, op, val) => makeQuery(col, [...filters, { field, op, val }]),
    limit: () => makeQuery(col, filters),
    get: async () => {
      const docs = [];
      for (const [path, d] of store.entries()) {
        if (!path.startsWith(`${col}/`)) continue;
        const ok = filters.every(({ field, op, val }) => {
          if (op === '==') return d[field] === val;
          if (op === 'array-contains') return Array.isArray(d[field]) && d[field].includes(val);
          return false;
        });
        if (ok) {
          const id = path.slice(col.length + 1);
          docs.push({ id, ref: { id, path }, data: () => cloneData(d) });
        }
      }
      return { empty: docs.length === 0, docs, size: docs.length };
    },
  };
}

function setupHarness() {
  store.clear();
  batchCommits.length = 0;
  capturedLogs.length = 0;
  sentMulticasts.length = 0;
  setVisionClientForTest(null);
  setGeminiGenerateContentForTest(null);
  installLogSpy();

  db.collection = (col) => ({
    doc: (id) => makeDocRef(col, id),
    where: (field, op, val) => makeQuery(col, [{ field, op, val }]),
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

  db.batch = () => {
    const ops = [];
    return {
      set: (ref, data, opts) => ops.push({ type: 'set', path: ref.path, data: cloneData(data), opts }),
      delete: (ref) => ops.push({ type: 'delete', path: ref.path }),
      commit: async () => {
        if (ops.length > 500) {
          throw new Error(`Batch exceeded 500 ops limit (${ops.length})`);
        }
        batchCommits.push(ops.length);
        for (const op of ops) {
          if (op.type === 'set') {
            if (op.opts?.merge && store.has(op.path)) {
              store.set(op.path, { ...store.get(op.path), ...op.data });
            } else {
              store.set(op.path, op.data);
            }
          } else if (op.type === 'delete') {
            store.delete(op.path);
          }
        }
      },
    };
  };

  db.runTransaction = async (callback) => {
    const ops = [];
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
      set: (ref, data, opts) => ops.push({ type: 'set', path: ref.path, data: cloneData(data), opts }),
      update: (ref, data) => ops.push({ type: 'update', path: ref.path, data: cloneData(data) }),
      delete: (ref) => ops.push({ type: 'delete', path: ref.path }),
    };
    const result = await callback(tx);
    if (ops.length > 500) {
      throw new Error(`Transaction exceeded 500 ops limit (${ops.length})`);
    }
    for (const op of ops) {
      if (op.type === 'set') {
        if (op.opts?.merge && store.has(op.path)) {
          store.set(op.path, { ...store.get(op.path), ...op.data });
        } else {
          store.set(op.path, op.data);
        }
      } else if (op.type === 'update') {
        const cur = store.get(op.path) ?? {};
        store.set(op.path, { ...cur, ...op.data });
      } else if (op.type === 'delete') {
        store.delete(op.path);
      }
    }
    return result;
  };

  messaging.sendEachForMulticast = async (msg) => {
    sentMulticasts.push(cloneData(msg));
    return { successCount: msg.tokens.length, failureCount: 0, responses: [] };
  };
}

function seedSchool(overrides = {}) {
  store.set('schools/tokyo.ac.jp', {
    name: '東京学校',
    admins: ['admin_uid'],
    teachers: ['homeroom1a@tokyo.ac.jp', 'teacher2@tokyo.ac.jp'],
    teacherProfiles: {
      'homeroom1a@tokyo.ac.jp': { name: '佐藤太郎', homeroom: { grade: 1, course: '農業' } },
      'teacher2@tokyo.ac.jp': { name: '田中花子', homeroom: null },
    },
    grades: [1, 2],
    courses: ['農業', '観光'],
    ...overrides,
  });
}

const adminAuth = { uid: 'admin_uid', token: { email: 'admin@tokyo.ac.jp', email_verified: true } };
const homeroomAuth = { uid: 'homeroom_uid', token: { email: 'homeroom1a@tokyo.ac.jp', email_verified: true } };
const teacher2Auth = { uid: 'teacher2_uid', token: { email: 'teacher2@tokyo.ac.jp', email_verified: true } };

async function buildFlatXlsxBuffer(rows, sheetCount = 1) {
  const wb = new ExcelJS.Workbook();
  for (let s = 0; s < sheetCount; s++) {
    const ws = wb.addWorksheet(`Sheet${s + 1}`);
    if (s === 0) {
      for (const r of rows) ws.addRow(r);
    } else {
      ws.addRow(['date', 'period', 'subject']);
    }
  }
  return Buffer.from(await wb.xlsx.writeBuffer());
}

async function buildSchoolGridXlsxBuffer() {
  const grid = JSON.parse(
    readFileSync(new URL('./fixtures/school_rows.json', import.meta.url), 'utf8'),
  );
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('2026年度後期');
  for (const r of grid) ws.addRow(r);
  return Buffer.from(await wb.xlsx.writeBuffer());
}

function buildMinimalPdfBuffer(textItems) {
  // textItems: array of { text, x, y }
  const streamOps = textItems
    .map(({ text, x, y }) => `BT /F1 12 Tf ${x} ${y} Td (${text}) Tj ET`)
    .join('\n');
  const objects = [
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
    '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
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

function makeVisionWord(text, left, top, right, bottom) {
  return {
    text,
    boundingBox: {
      vertices: [
        { x: left, y: top },
        { x: right, y: top },
        { x: right, y: bottom },
        { x: left, y: bottom },
      ],
    },
    symbols: [...text].map((ch, idx) => {
      const step = (right - left) / Math.max(1, text.length);
      const l = Math.round(left + idx * step);
      const r = Math.round(left + (idx + 1) * step);
      return {
        text: ch,
        boundingBox: {
          vertices: [
            { x: l, y: top },
            { x: r, y: top },
            { x: r, y: bottom },
            { x: l, y: bottom },
          ],
        },
      };
    }),
  };
}

function buildZipBombBuffer(uncompressedBytes) {
  const name = Buffer.from('xl/worksheets/sheet1.xml', 'utf8');
  const localHeader = Buffer.alloc(30 + name.length);
  localHeader.writeUInt32LE(0x04034b50, 0);
  name.copy(localHeader, 30);

  const cdOffset = localHeader.length;
  const cdHeader = Buffer.alloc(46 + name.length);
  cdHeader.writeUInt32LE(0x02014b50, 0);
  cdHeader.writeUInt32LE(uncompressedBytes, 24);
  cdHeader.writeUInt16LE(name.length, 28);
  name.copy(cdHeader, 46);

  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(1, 8);
  eocd.writeUInt16LE(1, 10);
  eocd.writeUInt32LE(cdHeader.length, 12);
  eocd.writeUInt32LE(cdOffset, 16);

  return Buffer.concat([localHeader, cdHeader, eocd]);
}

// Actual Shift_JIS (CP932) bytes produced from:
// 曜日,時限,科目,教員,教室,メモ\r\n
// 月,1,数学①,髙橋,101,"線形代数, 第1回"\r\n
// 火,2,英語②,﨑山,202,会話\r\n
const CP932_EXCEL_CSV_BASE64 =
  'l2qT+iyOnozALInIltosi7OI9SyLs466LIOBg4INCoyOLDEskJSKd4dALPv8i7QsMTAxLCKQ/IxgkeOQlCwgkeYxifEiDQqJziwyLIlwjOqHQSz6sY5SLDIwMiyJ75hiDQo=';

// ---------------------------------------------------------------------------
// 1. CSV encoding detection (UTF-8 with/without BOM + Shift_JIS/CP932) + XLSX + JSON removal
// ---------------------------------------------------------------------------
test('decodeCsvBuffer auto-detects UTF-8 (with/without BOM) and Excel Shift_JIS (CP932 with ①②, 髙, 﨑)', async () => {
  setupHarness();
  seedSchool();

  const sjisBuf = Buffer.from(CP932_EXCEL_CSV_BASE64, 'base64');
  const decoded = decodeCsvBuffer(sjisBuf);
  assert.equal(decoded.encoding, 'shift_jis');
  assert.ok(decoded.text.includes('数学①'));
  assert.ok(decoded.text.includes('髙橋'));
  assert.ok(decoded.text.includes('英語②'));
  assert.ok(decoded.text.includes('﨑山'));
  assert.ok(!decoded.text.includes('\uFFFD'));

  // Preview directly from CP932 CSV buffer
  const sjisPreview = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      mode: 'merge',
      fileName: 'excel_sjis.csv',
      mimeType: 'text/csv',
      fileBase64: CP932_EXCEL_CSV_BASE64,
      dateRange: { start: '2026-06-01', end: '2026-06-05' },
    },
  });
  assert.equal(sjisPreview.parseMethod, 'header_mapper');
  assert.equal(sjisPreview.usedAi, false);
  assert.equal(sjisPreview.changedDaysCount, 2);
  // NFKC normalizes ①/② -> 1/2 while keeping 髙/﨑 intact
  assert.equal(sjisPreview.diffPreview[0].after.subject, '数学1');
  assert.equal(sjisPreview.diffPreview[0].after.teacher, '髙橋');
  assert.equal(sjisPreview.diffPreview[1].after.subject, '英語2');
  assert.equal(sjisPreview.diffPreview[1].after.teacher, '﨑山');

  // UTF-8 with BOM + no BOM
  const utf8Bom = decodeCsvBuffer(Buffer.from('\uFEFFdate,period,subject\n2026-06-01,1,数学\n', 'utf8'));
  assert.equal(utf8Bom.encoding, 'utf-8-bom');
  const utf8Plain = decodeCsvBuffer(Buffer.from('date,period,subject\n2026-06-01,1,数学\n', 'utf8'));
  assert.equal(utf8Plain.encoding, 'utf-8');

  // .json is no longer accepted (reduced attack surface)
  await assert.rejects(
    () =>
      previewTimetableImport.run({
        auth: homeroomAuth,
        data: {
          grade: 1,
          course: '農業',
          fileName: 'tt.json',
          mimeType: 'application/json',
          fileBase64: Buffer.from('[]', 'utf8').toString('base64'),
        },
      }),
    (err) => err.code === 'invalid-argument',
  );
});

test('decodeCsvBuffer and previewTimetableImport throw failed-precondition with reason: sjis_unsupported_runtime when runtime lacks Shift_JIS support', async () => {
  setupHarness();
  seedSchool();

  assert.equal(checkShiftJisSupport(), true);

  const sjisBuf = Buffer.from(CP932_EXCEL_CSV_BASE64, 'base64');

  try {
    setShiftJisSupportForTest(false);

    // decodeCsvBuffer directly
    assert.throws(
      () => decodeCsvBuffer(sjisBuf),
      (err) => {
        assert.equal(err.code, 'failed-precondition');
        assert.equal(err.details?.reason, 'sjis_unsupported_runtime');
        return true;
      },
    );

    // previewTimetableImport call
    await assert.rejects(
      () =>
        previewTimetableImport.run({
          auth: homeroomAuth,
          data: {
            grade: 1,
            course: '農業',
            mode: 'merge',
            fileName: 'excel_sjis.csv',
            mimeType: 'text/csv',
            fileBase64: CP932_EXCEL_CSV_BASE64,
            dateRange: { start: '2026-06-01', end: '2026-06-05' },
          },
        }),
      (err) => {
        assert.equal(err.code, 'failed-precondition');
        assert.equal(err.details?.reason, 'sjis_unsupported_runtime');
        return true;
      },
    );

    // Valid UTF-8 CSV continues to work even if Shift_JIS is unsupported
    const utf8Buf = Buffer.from('date,period,subject\n2026-06-01,1,数学\n', 'utf8');
    const utf8Decoded = decodeCsvBuffer(utf8Buf);
    assert.equal(utf8Decoded.encoding, 'utf-8');
    assert.ok(utf8Decoded.text.includes('数学'));
  } finally {
    setShiftJisSupportForTest(null);
  }
});

test('previewTimetableImport parses flat XLSX & school-grid XLSX with accurate parseMethod/usedAi', async () => {
  setupHarness();
  seedSchool();

  const flatBuf = await buildFlatXlsxBuffer([
    ['date', 'period', 'subject', 'teacher', 'room', 'grade', 'course'],
    ['2026-06-08', '1', '化学', '伊藤先生', 'Lab1', '1', '農業'],
    ['2026-06-08', '2', '他クラス', '他先生', '999', '2', '観光'],
  ]);
  const flatPreview = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      mode: 'merge',
      fileName: 'flat.xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      fileBase64: flatBuf.toString('base64'),
    },
  });
  assert.equal(flatPreview.parseMethod, 'header_mapper');
  assert.equal(flatPreview.usedAi, false);
  assert.equal(flatPreview.changedDaysCount, 1);
  assert.equal(flatPreview.diffPreview[0].after.subject, '化学');

  const gridBuf = await buildSchoolGridXlsxBuffer();
  const gridPreview = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      mode: 'merge',
      fileName: '2026年度後期.xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      fileBase64: gridBuf.toString('base64'),
    },
  });
  assert.equal(gridPreview.parseMethod, 'school_matrix');
  assert.equal(gridPreview.usedAi, false);
  assert.equal(gridPreview.changedDaysCount, 9);
  const oct26 = gridPreview.diffPreview.find((d) => d.date === '2026-10-26' && d.period === '1-2');
  assert.equal(oct26.after.subject, 'IT概論2');
});

// ---------------------------------------------------------------------------
// 2. Image OCR (ocr_grid & AI fallback) + PDF (scanned & text/AI) + invalidRows
// ---------------------------------------------------------------------------
test('Image OCR reconstructs coordinate grid without AI when structured, and masks names before AI fallback without sending inlineData', async () => {
  setupHarness();
  seedSchool();

  const samplePng = await sharp({
    create: { width: 800, height: 600, channels: 3, background: '#FFFFFF' },
  }).png().toBuffer();

  // Case A: Weekly grid table in image -> deterministic `ocr_grid`, Gemini NOT called
  let geminiCalls = 0;
  setGeminiGenerateContentForTest(async () => {
    geminiCalls += 1;
    return { text: '{}' };
  });
  setVisionClientForTest({
    documentTextDetection: async () => [{
      fullTextAnnotation: {
        pages: [{
          blocks: [{
            paragraphs: [{
              words: [
                makeVisionWord('時限', 20, 20, 90, 45),
                makeVisionWord('月', 160, 20, 210, 45),
                makeVisionWord('水', 320, 20, 370, 45),
                makeVisionWord('1限', 20, 80, 90, 105),
                makeVisionWord('数学', 155, 80, 220, 105),
                makeVisionWord('英語', 315, 80, 380, 105),
              ],
            }],
          }],
        }],
      },
    }],
  });

  const ocrGridRes = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'board.png',
      mimeType: 'image/png',
      fileBase64: samplePng.toString('base64'),
      dateRange: { start: '2026-06-01', end: '2026-06-05' },
    },
  });
  assert.equal(ocrGridRes.parseMethod, 'ocr_grid');
  assert.equal(ocrGridRes.usedAi, false);
  assert.equal(ocrGridRes.maskedPreviewText, null);
  assert.equal(geminiCalls, 0);
  assert.equal(ocrGridRes.changedDaysCount, 2); // Mon 6/1 & Wed 6/3

  // Case B: Unfamiliar narrative image -> Vision OCR -> masked text sent to Gemini (NO inlineData!)
  setVisionClientForTest({
    documentTextDetection: async () => [{
      fullTextAnnotation: {
        pages: [{
          blocks: [{
            paragraphs: [{
              words: [
                makeVisionWord('来週火曜日1時間目は佐藤太郎の物理実験です', 40, 40, 600, 70),
              ],
            }],
          }],
        }],
      },
    }],
  });

  let capturedGeminiConfig = null;
  setGeminiGenerateContentForTest(async (cfg) => {
    capturedGeminiConfig = cfg;
    return {
      text: JSON.stringify({
        slots: [
          { dayOfWeek: '火', period: '1', subject: '物理実験', teacher: '[TEACHER_1]', room: '理科室' },
          { dayOfWeek: '水', period: '99', subject: '無効なコマ' },
        ],
      }),
    };
  });

  const aiImageRes = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
      fileBase64: samplePng.toString('base64'),
      dateRange: { start: '2026-06-01', end: '2026-06-05' },
    },
  });

  assert.equal(aiImageRes.parseMethod, 'ai');
  assert.equal(aiImageRes.usedAi, true);
  assert.equal(aiImageRes.changedDaysCount, 1);
  assert.equal(aiImageRes.invalidRows.length, 1);
  assert.match(aiImageRes.invalidRows[0].reason, /Unknown period: 99/);

  const serializedConfig = JSON.stringify(capturedGeminiConfig);
  assert.ok(!serializedConfig.includes('inlineData'), 'Raw image must NEVER be sent to Gemini');
  assert.ok(!serializedConfig.includes('佐藤太郎'), 'Teacher name must be masked before Gemini');
  assert.ok(serializedConfig.includes('[TEACHER_1]'));
  assert.ok(aiImageRes.maskedPreviewText?.includes('[TEACHER_1]'));
  assert.ok(!aiImageRes.maskedPreviewText?.includes('佐藤太郎'));
});

test('PDF import rejects scanned PDFs (scanned_pdf), parses structured PDFs without AI, and falls back to masked AI text', async () => {
  setupHarness();
  seedSchool();

  // Scanned PDF (< 50 chars/page) -> invalid-argument reason: scanned_pdf, Gemini NOT called
  let geminiCalls = 0;
  setGeminiGenerateContentForTest(async () => {
    geminiCalls += 1;
    return { text: '{}' };
  });
  const scannedPdf = buildMinimalPdfBuffer([{ text: 'Hi', x: 10, y: 700 }]);
  await assert.rejects(
    () =>
      previewTimetableImport.run({
        auth: homeroomAuth,
        data: {
          grade: 1,
          course: '農業',
          fileName: 'scan.pdf',
          mimeType: 'application/pdf',
          fileBase64: scannedPdf.toString('base64'),
        },
      }),
    (err) => err.code === 'invalid-argument' && err.details?.reason === 'scanned_pdf',
  );
  assert.equal(geminiCalls, 0);

  // Structured tabular PDF (>= 50 chars/page) -> deterministic `ocr_grid`, Gemini NOT called
  const structuredPdf = buildMinimalPdfBuffer([
    { text: 'date', x: 30, y: 740 },
    { text: 'period', x: 160, y: 740 },
    { text: 'subject', x: 260, y: 740 },
    { text: 'room', x: 380, y: 740 },
    { text: '2026-06-08', x: 30, y: 710 },
    { text: '1', x: 160, y: 710 },
    { text: 'Mathematics', x: 260, y: 710 },
    { text: 'R101', x: 380, y: 710 },
    { text: '2026-06-09', x: 30, y: 680 },
    { text: '2', x: 160, y: 680 },
    { text: 'Chemistry', x: 260, y: 680 },
    { text: 'Lab2', x: 380, y: 680 },
  ]);
  const pdfGridRes = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'table.pdf',
      mimeType: 'application/pdf',
      fileBase64: structuredPdf.toString('base64'),
    },
  });
  assert.equal(pdfGridRes.parseMethod, 'ocr_grid');
  assert.equal(pdfGridRes.usedAi, false);
  assert.equal(pdfGridRes.changedDaysCount, 2);
  assert.equal(geminiCalls, 0);

  // Text PDF with enough chars (>= 50 chars/page) in unfamiliar layout -> AI fallback with masking
  const textPdf = buildMinimalPdfBuffer([
    { text: '2026-06-08 Period 1 Algebra taught by Teacher Sato Tarou in Room 201.', x: 20, y: 740 },
    { text: 'Extra school bulletin notes so total extracted text exceeds fifty chars.', x: 20, y: 710 },
  ]);
  // Seed a teacher matching ASCII name so masking replaces it too
  seedSchool({
    teacherProfiles: {
      'homeroom1a@tokyo.ac.jp': { name: 'Sato Tarou', homeroom: { grade: 1, course: '農業' } },
    },
  });

  let sentToGemini = '';
  setGeminiGenerateContentForTest(async (cfg) => {
    sentToGemini = JSON.stringify(cfg.contents);
    return {
      text: JSON.stringify({
        slots: [
          { date: '2026-06-08', period: '1', subject: 'Algebra', teacher: '[TEACHER_1]', room: '201' },
        ],
      }),
    };
  });

  const pdfAiRes = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'notice.pdf',
      mimeType: 'application/pdf',
      fileBase64: textPdf.toString('base64'),
    },
  });
  assert.equal(pdfAiRes.parseMethod, 'ai');
  assert.equal(pdfAiRes.usedAi, true);
  assert.equal(pdfAiRes.changedDaysCount, 1);
  assert.ok(!sentToGemini.includes('inlineData'));
  assert.ok(!sentToGemini.includes('Sato Tarou'));
  assert.ok(sentToGemini.includes('[TEACHER_1]'));
  assert.equal(pdfAiRes.diffPreview[0].after.teacher, 'Sato Tarou');
});

// ---------------------------------------------------------------------------
// 3. Security & resource limits: 10MB, 5000 rows, 10 sheets, ZIP bomb
// ---------------------------------------------------------------------------
test('previewTimetableImport rejects >10MB files, >5000 rows, >10 sheets, and XLSX zip bombs', async () => {
  setupHarness();
  seedSchool();

  await assert.rejects(
    () =>
      previewTimetableImport.run({
        auth: adminAuth,
        data: {
          grade: 1,
          course: '農業',
          fileName: 'huge.csv',
          mimeType: 'text/csv',
          fileBase64: 'A'.repeat(Math.ceil(MAX_IMPORT_FILE_BYTES * 1.41)),
        },
      }),
    (err) => err.code === 'invalid-argument',
  );

  const tooManyRows = ['date,period,subject']
    .concat(Array.from({ length: MAX_IMPORT_ROWS + 5 }, () => '2026-06-01,1,数学'))
    .join('\n');
  await assert.rejects(
    () =>
      previewTimetableImport.run({
        auth: adminAuth,
        data: {
          grade: 1,
          course: '農業',
          fileName: 'many.csv',
          mimeType: 'text/csv',
          fileBase64: Buffer.from(tooManyRows, 'utf8').toString('base64'),
        },
      }),
    (err) => err.code === 'invalid-argument',
  );

  const manySheetsBuf = await buildFlatXlsxBuffer(
    [['date', 'period', 'subject'], ['2026-06-01', '1', '数学']],
    MAX_IMPORT_SHEETS + 1,
  );
  await assert.rejects(
    () =>
      previewTimetableImport.run({
        auth: adminAuth,
        data: {
          grade: 1,
          course: '農業',
          fileName: 'sheets.xlsx',
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          fileBase64: manySheetsBuf.toString('base64'),
        },
      }),
    (err) => err.code === 'invalid-argument',
  );

  const bombBuf = buildZipBombBuffer(MAX_IMPORT_XLSX_UNCOMPRESSED_BYTES + 1024);
  assert.throws(
    () => validateXlsxZip(bombBuf),
    (err) => err.code === 'invalid-argument',
  );
  await assert.rejects(
    () =>
      previewTimetableImport.run({
        auth: adminAuth,
        data: {
          grade: 1,
          course: '農業',
          fileName: 'bomb.xlsx',
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          fileBase64: bombBuf.toString('base64'),
        },
      }),
    (err) => err.code === 'invalid-argument',
  );
});

// ---------------------------------------------------------------------------
// 4. Exclusions + 2028 provisional equinox flag
// ---------------------------------------------------------------------------
test('Excludes holidays (with 2028 provisional flag), closedDateRanges, non-school days, and manual dates', async () => {
  setupHarness();
  seedSchool({
    policy: {
      schemaVersion: 1,
      timetableImport: {
        allowedImporters: 'all_teachers',
        schoolDays: ['月', '火', '水', '木', '金'],
        excludeNationalHolidays: true,
        closedDateRanges: [{ start: '2026-09-24', end: '2026-09-25', label: '創立記念休業' }],
      },
    },
  });

  const csv = [
    'date,period,subject',
    '2026-05-06,1,祝日',
    '2026-09-22,1,国民の休日',
    '2027-03-22,1,春分振替',
    '2028-03-20,1,2028春分',
    '2028-09-22,1,2028秋分',
    '2026-09-24,1,休校日',
    '2026-09-26,1,土曜日',
    '2026-06-01,1,手動除外',
    '2026-06-02,1,有効授業',
  ].join('\n');

  const preview = await previewTimetableImport.run({
    auth: adminAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'holidays.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from(csv, 'utf8').toString('base64'),
      excludedDates: ['2026-06-01'],
    },
  });

  assert.equal(preview.changedDaysCount, 1);
  assert.deepEqual(preview.excludedDates, [
    { date: '2026-05-06', reason: 'national_holiday', label: '休日', provisional: false },
    { date: '2026-06-01', reason: 'manual', label: '', provisional: false },
    { date: '2026-09-22', reason: 'national_holiday', label: '休日', provisional: false },
    { date: '2026-09-24', reason: 'closed_range', label: '創立記念休業', provisional: false },
    { date: '2026-09-26', reason: 'non_school_day', label: '土', provisional: false },
    { date: '2027-03-22', reason: 'national_holiday', label: '休日', provisional: false },
    { date: '2028-03-20', reason: 'national_holiday', label: '春分の日', provisional: true },
    { date: '2028-09-22', reason: 'national_holiday', label: '秋分の日', provisional: true },
  ]);

  const confirmed = await confirmTimetableImport.run({
    auth: adminAuth,
    data: { draftId: preview.draftId, notifyStudents: false },
  });
  assert.equal(confirmed.appliedDays, 1);
  assert.ok(store.has(`school_days/${dayDocId('tokyo.ac.jp', { grade: 1, course: '農業', date: '2026-06-02' })}`));
  assert.ok(!store.has(`school_days/${dayDocId('tokyo.ac.jp', { grade: 1, course: '農業', date: '2026-09-22' })}`));

  // excludeNationalHolidays = false includes 2026-09-22
  store.set('schools/tokyo.ac.jp', {
    ...store.get('schools/tokyo.ac.jp'),
    policy: {
      schemaVersion: 1,
      timetableImport: { excludeNationalHolidays: false },
    },
  });
  const previewWithHolidays = await previewTimetableImport.run({
    auth: adminAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'holidays_inc.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from('date,period,subject\n2026-09-22,1,特別授業\n', 'utf8').toString('base64'),
    },
  });
  assert.equal(previewWithHolidays.changedDaysCount, 1);
  assert.equal(previewWithHolidays.excludedDates.length, 0);
});

// ---------------------------------------------------------------------------
// 5. Periods priority (school.periods vs periods.dart fallback)
// ---------------------------------------------------------------------------
test('resolveSchoolPeriods uses schools/{domain}.periods first and falls back to DEFAULT_IMPORT_PERIODS (1..6)', async () => {
  setupHarness();
  const customPeriods = [{ key: '1-2', label: '1・2限', start: '09:00', end: '10:30' }];
  assert.deepEqual(resolveSchoolPeriods({ periods: customPeriods }), customPeriods);
  assert.deepEqual(resolveSchoolPeriods({}), DEFAULT_IMPORT_PERIODS);

  seedSchool();
  const preview = await previewTimetableImport.run({
    auth: adminAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'fallback_periods.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from('date,period,subject\n2026-06-10,6,ゼミ\n', 'utf8').toString('base64'),
    },
  });
  await confirmTimetableImport.run({
    auth: adminAuth,
    data: { draftId: preview.draftId, notifyStudents: false },
  });
  assert.deepEqual(store.get('schools/tokyo.ac.jp').periods, DEFAULT_IMPORT_PERIODS);
});

// ---------------------------------------------------------------------------
// 6. merge vs replace diff + idempotent re-import
// ---------------------------------------------------------------------------
test('merge preserves untouched periods, replace removes missing periods, and re-import is idempotent', async () => {
  setupHarness();
  seedSchool({
    policy: { schemaVersion: 1, timetableImport: { replaceMode: 'allowed' } },
  });

  const dayId = dayDocId('tokyo.ac.jp', { grade: 1, course: '農業', date: '2026-06-15' });
  store.set(`school_days/${dayId}`, {
    domain: 'tokyo.ac.jp',
    grade: 1,
    course: '農業',
    date: '2026-06-15',
    slots: [
      { period: '1', subject: '国語', teacher: 'A', room: '101', note: '', status: 'normal' },
      { period: '2', subject: '英語', teacher: 'B', room: '102', note: '', status: 'normal' },
    ],
  });

  const mergeFile = Buffer.from(
    'date,period,subject,teacher,room\n2026-06-15,1,現代文,A,101\n',
    'utf8',
  ).toString('base64');
  const mergePreview = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      mode: 'merge',
      fileName: 'm.csv',
      mimeType: 'text/csv',
      fileBase64: mergeFile,
    },
  });
  assert.deepEqual(mergePreview.summary, { added: 0, updated: 1, removed: 0, unchanged: 1 });
  const mergeConfirm = await confirmTimetableImport.run({
    auth: homeroomAuth,
    data: { draftId: mergePreview.draftId, notifyStudents: false },
  });
  assert.equal(mergeConfirm.appliedDays, 1);
  assert.equal(store.get(`school_days/${dayId}`).slots.length, 2);

  const idemPreview = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      mode: 'merge',
      fileName: 'm.csv',
      mimeType: 'text/csv',
      fileBase64: mergeFile,
    },
  });
  assert.equal(idemPreview.changedDaysCount, 0);
  assert.deepEqual(idemPreview.summary, { added: 0, updated: 0, removed: 0, unchanged: 2 });
  const idemConfirm = await confirmTimetableImport.run({
    auth: homeroomAuth,
    data: { draftId: idemPreview.draftId, notifyStudents: true },
  });
  assert.equal(idemConfirm.appliedDays, 0);
  assert.equal(idemConfirm.pushed, 0);
  assert.equal(sentMulticasts.length, 0);

  const replacePreview = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      mode: 'replace',
      fileName: 'r.csv',
      mimeType: 'text/csv',
      fileBase64: mergeFile,
    },
  });
  assert.deepEqual(replacePreview.summary, { added: 0, updated: 0, removed: 1, unchanged: 1 });
  await confirmTimetableImport.run({
    auth: homeroomAuth,
    data: { draftId: replacePreview.draftId, notifyStudents: false },
  });
  assert.deepEqual(
    store.get(`school_days/${dayId}`).slots.map((s) => s.period),
    ['1'],
  );
});

// ---------------------------------------------------------------------------
// 7. Dynamic policy re-check at confirm & revert time
// ---------------------------------------------------------------------------
test('confirmTimetableImport & revertTimetableImport re-check CURRENT school policy (not draft-creation policy)', async () => {
  setupHarness();
  seedSchool({
    policy: {
      schemaVersion: 1,
      revision: 1,
      timetableImport: {
        allowedImporters: 'homeroom_and_admins',
        replaceMode: 'allowed',
      },
    },
  });

  const replacePreview = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      mode: 'replace',
      fileName: 'r.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from('date,period,subject\n2026-06-16,1,数学\n', 'utf8').toString('base64'),
    },
  });

  await setSchoolPolicy.run({
    auth: adminAuth,
    data: {
      expectedRevision: 1,
      policy: { timetableImport: { replaceMode: 'disabled' } },
    },
  });

  await assert.rejects(
    () =>
      confirmTimetableImport.run({
        auth: homeroomAuth,
        data: { draftId: replacePreview.draftId, notifyStudents: false },
      }),
    (err) => err.code === 'permission-denied',
  );

  const mergePreview = await previewTimetableImport.run({
    auth: homeroomAuth,
    data: {
      grade: 1,
      course: '農業',
      mode: 'merge',
      fileName: 'm.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from('date,period,subject\n2026-06-17,1,数学\n', 'utf8').toString('base64'),
    },
  });
  const mergeConfirmed = await confirmTimetableImport.run({
    auth: homeroomAuth,
    data: { draftId: mergePreview.draftId, notifyStudents: false },
  });

  await setSchoolPolicy.run({
    auth: adminAuth,
    data: {
      expectedRevision: 2,
      policy: { timetableImport: { allowedImporters: 'admins_only' } },
    },
  });

  await assert.rejects(
    () => revertTimetableImport.run({ auth: homeroomAuth, data: { importId: mergeConfirmed.importId } }),
    (err) => err.code === 'permission-denied',
  );
  const adminRevert = await revertTimetableImport.run({
    auth: adminAuth,
    data: { importId: mergeConfirmed.importId },
  });
  assert.equal(adminRevert.ok, true);
});

// ---------------------------------------------------------------------------
// 8. Optimistic concurrency on confirm & revert
// ---------------------------------------------------------------------------
test('Optimistic concurrency aborts confirm or revert when school_days changed concurrently', async () => {
  setupHarness();
  seedSchool();

  const dayId = dayDocId('tokyo.ac.jp', { grade: 1, course: '農業', date: '2026-06-18' });
  const p1 = await previewTimetableImport.run({
    auth: adminAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'c1.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from('date,period,subject\n2026-06-18,1,生物\n', 'utf8').toString('base64'),
    },
  });

  store.set(`school_days/${dayId}`, {
    domain: 'tokyo.ac.jp',
    grade: 1,
    course: '農業',
    date: '2026-06-18',
    slots: [{ period: '1', subject: '別の授業', teacher: '', room: '', note: '', status: 'normal' }],
  });
  await assert.rejects(
    () => confirmTimetableImport.run({ auth: adminAuth, data: { draftId: p1.draftId } }),
    (err) => err.code === 'aborted' && err.details?.reason === 'timetable_changed',
  );

  const p2 = await previewTimetableImport.run({
    auth: adminAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'c2.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from('date,period,subject\n2026-06-18,1,生物\n', 'utf8').toString('base64'),
    },
  });
  const c2 = await confirmTimetableImport.run({
    auth: adminAuth,
    data: { draftId: p2.draftId, notifyStudents: false },
  });

  store.set(`school_days/${dayId}`, {
    ...store.get(`school_days/${dayId}`),
    slots: [{ period: '1', subject: '手動上書き', teacher: '', room: '', note: '', status: 'normal' }],
    hash: 'modified_after_import',
  });
  await assert.rejects(
    () => revertTimetableImport.run({ auth: adminAuth, data: { importId: c2.importId } }),
    (err) => err.code === 'aborted' && err.details?.reason === 'timetable_changed',
  );
});

// ---------------------------------------------------------------------------
// 9. revertTimetableImport: undoWindowDays (1d & 30d), creator/admin, single-use
// ---------------------------------------------------------------------------
test('revertTimetableImport respects policy.timetableImport.undoWindowDays (1-day & 30-day boundaries)', async () => {
  setupHarness();

  // A) undoWindowDays = 1: expires after 25 hours, succeeds at 23 hours
  seedSchool({
    policy: {
      schemaVersion: 1,
      timetableImport: { allowedImporters: 'all_teachers', undoWindowDays: 1 },
    },
  });
  let clock = new Date('2026-06-01T00:00:00Z');
  const school1 = store.get('schools/tokyo.ac.jp');

  const p1 = await runPreviewTimetableImport(
    'tokyo.ac.jp',
    school1,
    homeroomAuth,
    {
      grade: 1,
      course: '農業',
      fileName: 'w1.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from('date,period,subject\n2026-06-22,1,新しい授業\n', 'utf8').toString('base64'),
    },
    { db, now: () => clock },
  );
  const c1 = await runConfirmTimetableImport(
    'tokyo.ac.jp',
    school1,
    homeroomAuth,
    { draftId: p1.draftId, notifyStudents: false },
    { db, now: () => clock },
  );

  clock = new Date('2026-06-02T01:00:00Z'); // 25h (> 1 day) -> rejected
  await assert.rejects(
    () => runRevertTimetableImport('tokyo.ac.jp', school1, homeroomAuth, { importId: c1.importId }, { db, now: () => clock }),
    (err) => err.code === 'failed-precondition',
  );

  clock = new Date('2026-06-01T23:00:00Z'); // 23h (< 1 day) -> succeeds
  const r1 = await runRevertTimetableImport('tokyo.ac.jp', school1, homeroomAuth, { importId: c1.importId }, { db, now: () => clock });
  assert.equal(r1.ok, true);

  // B) undoWindowDays = 30: expires after 30d + 1h, succeeds at 29d
  seedSchool({
    policy: {
      schemaVersion: 1,
      timetableImport: { allowedImporters: 'all_teachers', undoWindowDays: 30 },
    },
  });
  clock = new Date('2026-06-01T00:00:00Z');
  const school30 = store.get('schools/tokyo.ac.jp');
  const existingDayId = dayDocId('tokyo.ac.jp', { grade: 1, course: '農業', date: '2026-06-24' });
  const newDayId = dayDocId('tokyo.ac.jp', { grade: 1, course: '農業', date: '2026-06-25' });
  store.set(`school_days/${existingDayId}`, {
    domain: 'tokyo.ac.jp',
    grade: 1,
    course: '農業',
    date: '2026-06-24',
    slots: [{ period: '1', subject: '元の授業', teacher: '林先生', room: '100', note: '', status: 'normal' }],
  });

  const p30 = await runPreviewTimetableImport(
    'tokyo.ac.jp',
    school30,
    homeroomAuth,
    {
      grade: 1,
      course: '農業',
      fileName: 'w30.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from(
        'date,period,subject\n2026-06-24,1,新授業\n2026-06-25,2,新規日\n',
        'utf8',
      ).toString('base64'),
    },
    { db, now: () => clock },
  );
  const c30 = await runConfirmTimetableImport(
    'tokyo.ac.jp',
    school30,
    homeroomAuth,
    { draftId: p30.draftId, notifyStudents: false },
    { db, now: () => clock },
  );

  // Another non-admin teacher cannot revert homeroom teacher's import
  await assert.rejects(
    () => runRevertTimetableImport('tokyo.ac.jp', school30, teacher2Auth, { importId: c30.importId }, { db, now: () => clock }),
    (err) => err.code === 'permission-denied',
  );

  clock = new Date('2026-07-01T01:00:00Z'); // 30d + 1h -> rejected
  await assert.rejects(
    () => runRevertTimetableImport('tokyo.ac.jp', school30, homeroomAuth, { importId: c30.importId }, { db, now: () => clock }),
    (err) => err.code === 'failed-precondition',
  );

  clock = new Date('2026-06-30T00:00:00Z'); // 29d -> succeeds
  const r30 = await runRevertTimetableImport('tokyo.ac.jp', school30, homeroomAuth, { importId: c30.importId }, { db, now: () => clock });
  assert.equal(r30.revertedDays, 2);
  assert.equal(store.get(`school_days/${existingDayId}`).slots[0].subject, '元の授業');
  assert.ok(!store.has(`school_days/${newDayId}`));

  // Double-revert rejected
  await assert.rejects(
    () => runRevertTimetableImport('tokyo.ac.jp', school30, homeroomAuth, { importId: c30.importId }, { db, now: () => clock }),
    (err) => err.code === 'failed-precondition',
  );
});

// ---------------------------------------------------------------------------
// 10. Single combined summary push & privacy-safe logging
// ---------------------------------------------------------------------------
test('confirmTimetableImport sends 1 combined localized summary push (not per-day) and never logs PII/file contents', async () => {
  setupHarness();
  seedSchool();
  store.set('users/s_ja', { schoolDomain: 'tokyo.ac.jp', grade: '1', course: '農業', fcmToken: 'tok_ja', language: 'ja' });
  store.set('users/s_uz', { schoolDomain: 'tokyo.ac.jp', grade: '1', course: '農業', fcmToken: 'tok_uz', language: 'uz' });

  const secretTeacher = '機密教員太郎';
  const secretSubject = '秘密の特別講義';
  const csv = [
    'date,period,subject,teacher,room',
    `2026-06-29,1,${secretSubject},${secretTeacher},101`,
    `2026-06-30,1,${secretSubject},${secretTeacher},101`,
    `2026-07-01,1,${secretSubject},${secretTeacher},101`,
  ].join('\n');

  const preview = await previewTimetableImport.run({
    auth: adminAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'push.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from(csv, 'utf8').toString('base64'),
    },
  });
  const confirm = await confirmTimetableImport.run({
    auth: adminAuth,
    data: { draftId: preview.draftId, notifyStudents: true },
  });

  assert.equal(confirm.appliedDays, 3);
  assert.equal(confirm.pushed, 2);
  assert.equal(sentMulticasts.length, 2);
  assert.equal(sentMulticasts[0].notification.body, '時間割が更新されました（3日分）');
  assert.equal(sentMulticasts[1].notification.body, 'Jadval yangilandi: 3 kun');
  assert.equal(sentMulticasts[0].data.route, '/timetable');

  await revertTimetableImport.run({
    auth: adminAuth,
    data: { importId: confirm.importId },
  });

  const allLogsJson = JSON.stringify(capturedLogs);
  assert.ok(!allLogsJson.includes(secretTeacher), 'Teacher name must never appear in logs');
  assert.ok(!allLogsJson.includes(secretSubject), 'Subject name must never appear in logs');
});

// ---------------------------------------------------------------------------
// 11. >400 days chunked batch confirm & revert (405 days -> 2 batches, <= 500 ops)
// ---------------------------------------------------------------------------
test('Imports exceeding 400 days chunk confirm and revert across multiple batches cleanly', async () => {
  setupHarness();
  seedSchool();

  const lines = ['date,period,subject'];
  let cur = new Date('2026-04-01T00:00:00Z');
  let added = 0;
  store.set('schools/tokyo.ac.jp', {
    ...store.get('schools/tokyo.ac.jp'),
    policy: {
      schemaVersion: 1,
      timetableImport: { excludeNationalHolidays: false },
    },
  });

  while (added < BATCH_CHUNK_SIZE + 5) {
    const dow = cur.getUTCDay();
    if (dow >= 1 && dow <= 5) {
      lines.push(`${cur.toISOString().slice(0, 10)},1,通年授業`);
      added += 1;
    }
    cur = new Date(cur.getTime() + 86_400_000);
  }

  const preview = await previewTimetableImport.run({
    auth: adminAuth,
    data: {
      grade: 1,
      course: '農業',
      fileName: 'large.csv',
      mimeType: 'text/csv',
      fileBase64: Buffer.from(lines.join('\n'), 'utf8').toString('base64'),
    },
  });
  assert.equal(preview.changedDaysCount, 405);

  const confirm = await confirmTimetableImport.run({
    auth: adminAuth,
    data: { draftId: preview.draftId, notifyStudents: false },
  });
  assert.equal(confirm.appliedDays, 405);
  assert.deepEqual(batchCommits, [400, 5]);

  const revert = await revertTimetableImport.run({
    auth: adminAuth,
    data: { importId: confirm.importId },
  });
  assert.equal(revert.revertedDays, 405);
  assert.deepEqual(batchCommits, [400, 5, 400, 5]);

  logger.info = origLogger.info;
  logger.warn = origLogger.warn;
  logger.error = origLogger.error;
});
