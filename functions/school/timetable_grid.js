// Rebuilds a 2-D cell grid (`string[][]`) from positioned text boxes produced
// by Cloud Vision OCR (image) or pdfjs-dist (PDF). Pure, synchronous and
// dependency-free so it can be unit-tested without Vision/pdfjs.
//
// Token shape: { text, left, top, right, bottom } in a y-DOWN coordinate space.

export const MAX_GRID_TOKENS = 20_000;
export const MAX_GRID_ROWS = 2_000;
export const MAX_GRID_COLS = 60;

const median = (values) => {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

const ASCII_ALNUM_END = /[A-Za-z0-9]$/;
const ASCII_ALNUM_START = /^[A-Za-z0-9]/;

function joinText(a, b) {
  if (!a) return b;
  if (!b) return a;
  return ASCII_ALNUM_END.test(a) && ASCII_ALNUM_START.test(b) ? `${a} ${b}` : `${a}${b}`;
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
    left = Math.min(left, x);
    top = Math.min(top, y);
    right = Math.max(right, x);
    bottom = Math.max(bottom, y);
  }
  if (!Number.isFinite(left) || right <= left || bottom <= top) return null;
  return { left, top, right, bottom };
}

/**
 * Flattens Vision `fullTextAnnotation` into word tokens with bounding boxes.
 */
export function visionWordsToTokens(fullTextAnnotation) {
  const tokens = [];
  for (const page of fullTextAnnotation?.pages ?? []) {
    for (const block of page?.blocks ?? []) {
      for (const paragraph of block?.paragraphs ?? []) {
        for (const word of paragraph?.words ?? []) {
          const symbols = Array.isArray(word?.symbols) ? word.symbols : [];
          const text = symbols.length
            ? symbols.map((s) => String(s?.text ?? '')).join('')
            : String(word?.text ?? '');
          if (!text.trim()) continue;
          let box = boxFromVertices(word?.boundingBox?.vertices);
          if (!box && symbols.length) {
            const boxes = symbols.map((s) => boxFromVertices(s?.boundingBox?.vertices)).filter(Boolean);
            if (boxes.length) {
              box = {
                left: Math.min(...boxes.map((b) => b.left)),
                top: Math.min(...boxes.map((b) => b.top)),
                right: Math.max(...boxes.map((b) => b.right)),
                bottom: Math.max(...boxes.map((b) => b.bottom)),
              };
            }
          }
          if (!box) continue;
          tokens.push({ text: text.trim(), ...box });
          if (tokens.length > MAX_GRID_TOKENS) return tokens;
        }
      }
    }
  }
  return tokens;
}

/**
 * Groups tokens into rows (by vertical centre) and columns (by merged
 * horizontal bands), returning `string[][]`.
 *
 * 1. Rows: tokens sorted by centre-y; a new row starts when the gap to the
 *    running row centre exceeds 0.6 × median token height.
 * 2. Cells: horizontally adjacent tokens in a row whose gap is below
 *    0.8 × median height are merged into one cell token.
 * 3. Columns: x-intervals of all cell tokens (excluding page-wide titles) are
 *    merged into bands; each cell is assigned to the band containing its centre.
 */
export function reconstructGrid(rawTokens) {
  const tokens = (Array.isArray(rawTokens) ? rawTokens : [])
    .slice(0, MAX_GRID_TOKENS)
    .filter((t) => t && String(t.text ?? '').trim() && t.right > t.left && t.bottom > t.top);
  if (tokens.length === 0) return [];

  const medH = median(tokens.map((t) => t.bottom - t.top)) || 1;
  const rowTol = medH * 0.6;
  const cellGap = medH * 0.8;

  // 1. Rows
  const sorted = [...tokens].sort((a, b) => (a.top + a.bottom) - (b.top + b.bottom));
  const rows = [];
  for (const t of sorted) {
    const cy = (t.top + t.bottom) / 2;
    const cur = rows[rows.length - 1];
    if (cur && Math.abs(cy - cur.cy) <= rowTol) {
      cur.items.push(t);
      cur.cy = (cur.cy * (cur.items.length - 1) + cy) / cur.items.length;
    } else {
      if (rows.length >= MAX_GRID_ROWS) break;
      rows.push({ cy, items: [t] });
    }
  }

  // 2. Cells (merge adjacent tokens within a row)
  const cellRows = rows.map((r) => {
    const items = [...r.items].sort((a, b) => a.left - b.left);
    const cells = [];
    for (const t of items) {
      const last = cells[cells.length - 1];
      if (last && t.left - last.right <= cellGap) {
        last.text = joinText(last.text, String(t.text).trim());
        last.right = Math.max(last.right, t.right);
        last.top = Math.min(last.top, t.top);
        last.bottom = Math.max(last.bottom, t.bottom);
      } else {
        cells.push({ text: String(t.text).trim(), left: t.left, right: t.right, top: t.top, bottom: t.bottom });
      }
    }
    return cells;
  });

  // 3. Column bands
  const allCells = cellRows.flat();
  const minX = Math.min(...allCells.map((c) => c.left));
  const maxX = Math.max(...allCells.map((c) => c.right));
  const span = Math.max(1, maxX - minX);
  const bandSource = allCells
    .filter((c) => c.right - c.left <= span * 0.4)
    .map((c) => [c.left, c.right])
    .sort((a, b) => a[0] - b[0]);
  const bands = [];
  for (const [l, r] of bandSource) {
    const last = bands[bands.length - 1];
    if (last && l <= last[1]) {
      last[1] = Math.max(last[1], r);
    } else {
      bands.push([l, r]);
    }
  }
  if (bands.length === 0) bands.push([minX, maxX]);
  const usedBands = bands.slice(0, MAX_GRID_COLS);

  const bandIndexOf = (cell) => {
    const cx = (cell.left + cell.right) / 2;
    let best = 0;
    let bestDist = Infinity;
    for (let i = 0; i < usedBands.length; i++) {
      const [l, r] = usedBands[i];
      if (cx >= l && cx <= r) return i;
      const dist = cx < l ? l - cx : cx - r;
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  };

  return cellRows.map((cells) => {
    const row = new Array(usedBands.length).fill('');
    for (const c of cells) {
      const idx = bandIndexOf(c);
      row[idx] = row[idx] ? `${row[idx]} ${c.text}` : c.text;
    }
    return row;
  });
}

/** Serialises a grid as ` | `-separated lines (used as AI fallback input). */
export function gridToText(rows) {
  return rows
    .map((r) => r.map((c) => String(c ?? '').trim()).join(' | ').replace(/(\s\|\s)+$/g, ''))
    .filter((line) => line.replace(/[|\s]/g, '') !== '')
    .join('\n');
}
