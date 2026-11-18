function toUtf16BeHex(str) {
  let hex = '';
  for (let i = 0; i < str.length; i++) {
    hex += str.charCodeAt(i).toString(16).padStart(4, '0').toUpperCase();
  }
  return `<${hex}>`;
}

/**
 * Builds a valid PDF 1.4 document using Word-style Japanese CID Type0 fonts
 * (`/MS-Mincho` and `/YuMincho` with `/Encoding /UniJIS-UTF16-H`,
 * `/Registry (Adobe) /Ordering (Japan1)` and NO `/ToUnicode` map), so text
 * extraction strictly requires `pdfjs-dist` CMaps (`UniJIS-UTF16-H.bcmap` +
 * `Adobe-Japan1-UCS2.bcmap`).
 */
export function buildJapaneseCidPdfBuffer({
  pageCount = 1,
  lines = [
    { font: 'F1', y: 750, text: '課題提出者：山田太郎' },
    { font: 'F1', y: 720, text: '担当教員：高橋誠先生' },
    { font: 'F2', y: 690, text: '第1問：二次関数の頂点の座標を求めなさい。' },
    { font: 'F2', y: 660, text: '解答：平方完成より頂点は（２，－１）である。' },
  ],
} = {}) {
  const streamOps = lines
    .map((l) => `BT /${l.font} 12 Tf 40 ${l.y} Td ${toUtf16BeHex(l.text)} Tj ET`)
    .join('\n');

  const pageObjStart = 3;
  const kidsRefs = [];
  const pageObjs = [];
  const contentObjNum = pageObjStart + pageCount;
  const f1ObjNum = contentObjNum + 1;

  for (let p = 0; p < pageCount; p++) {
    const objNum = pageObjStart + p;
    kidsRefs.push(`${objNum} 0 R`);
    pageObjs.push(
      `${objNum} 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents ${contentObjNum} 0 R /Resources << /Font << /F1 ${f1ObjNum} 0 R /F2 ${f1ObjNum + 3} 0 R >> >> >> endobj\n`,
    );
  }

  const objects = [
    '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
    `2 0 obj << /Type /Pages /Kids [${kidsRefs.join(' ')}] /Count ${pageCount} >> endobj\n`,
    ...pageObjs,
    `${contentObjNum} 0 obj << /Length ${Buffer.byteLength(streamOps, 'utf8')} >> stream\n${streamOps}\nendstream endobj\n`,
    `${f1ObjNum} 0 obj << /Type /Font /Subtype /Type0 /BaseFont /MS-Mincho /Encoding /UniJIS-UTF16-H /DescendantFonts [${f1ObjNum + 1} 0 R] >> endobj\n`,
    `${f1ObjNum + 1} 0 obj << /Type /Font /Subtype /CIDFontType2 /BaseFont /MS-Mincho /CIDSystemInfo << /Registry (Adobe) /Ordering (Japan1) /Supplement 6 >> /FontDescriptor ${f1ObjNum + 2} 0 R /DW 1000 >> endobj\n`,
    `${f1ObjNum + 2} 0 obj << /Type /FontDescriptor /FontName /MS-Mincho /Flags 6 /FontBBox [0 -137 1000 859] /ItalicAngle 0 /Ascent 859 /Descent -141 /CapHeight 700 /StemV 70 >> endobj\n`,
    `${f1ObjNum + 3} 0 obj << /Type /Font /Subtype /Type0 /BaseFont /YuMincho /Encoding /UniJIS-UTF16-H /DescendantFonts [${f1ObjNum + 4} 0 R] >> endobj\n`,
    `${f1ObjNum + 4} 0 obj << /Type /Font /Subtype /CIDFontType2 /BaseFont /YuMincho /CIDSystemInfo << /Registry (Adobe) /Ordering (Japan1) /Supplement 6 >> /FontDescriptor ${f1ObjNum + 5} 0 R /DW 1000 >> endobj\n`,
    `${f1ObjNum + 5} 0 obj << /Type /FontDescriptor /FontName /YuMincho /Flags 6 /FontBBox [0 -137 1000 859] /ItalicAngle 0 /Ascent 859 /Descent -141 /CapHeight 700 /StemV 70 >> endobj\n`,
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
