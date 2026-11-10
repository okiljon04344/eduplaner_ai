import admin from 'firebase-admin';
import ExcelJS from 'exceljs';
import { readFileSync } from 'node:fs';
import { syncSchool } from '../school/sync.js';

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8085';
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'eduplannerai-97365';

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'eduplannerai-97365' });
}
const db = admin.firestore();

const domain = process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2]
  : 'school.test';
const notify = process.argv.includes('--notify');

const rawRows = JSON.parse(
  readFileSync(new URL('./fixtures/school_rows.json', import.meta.url), 'utf8')
);

// If --notify, change one fixture cell (room 201 -> 205 on 10/27 for 1st grade agriculture)
const rows = notify
  ? rawRows.map((row, ri) =>
      ri === 4
        ? row.map((cell, ci) => (ci === 4 ? '鈴木【205】' : cell))
        : row
    )
  : rawRows;

const xlsxOf = async (rs) => {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('s');
  rs.forEach((r) => ws.addRow(r));
  return Buffer.from(await wb.xlsx.writeBuffer());
};

const buffer = await xlsxOf(rows);
const meta = {
  id: 'file_test_xlsx',
  name: '2026年度 後期時間割.xlsx',
  modifiedTime: notify ? `m2_notified_${Date.now()}` : 'm1_initial',
};

// Seed school_secrets and base school document
await db.collection('school_secrets').doc(domain).set({
  refreshToken: 'mock_refresh_token',
}, { merge: true });

await db.collection('schools').doc(domain).set({
  name: 'テスト学校',
  admins: ['admin1'],
  file: { id: meta.id, name: meta.name },
}, { merge: true });

const pushes = [];
const deps = {
  db,
  now: () => new Date('2026-10-27T00:00:00Z'), // Tokyo 09:00 on Tuesday 2026-10-27
  sendMulticast: async (m) => {
    pushes.push(m);
    console.log(`[FCM Mock] Multicast sent to ${m.tokens.length} tokens:`, m.notification);
  },
  google: {
    refreshAccessToken: async () => 'mock_access_token',
    getFileMeta: async () => meta,
    downloadXlsx: async () => buffer,
  },
};

const res = await syncSchool(domain, { force: !notify, notify }, deps);
console.log('Sync result:', res);
console.log(`Change count: ${res.changes}`);
