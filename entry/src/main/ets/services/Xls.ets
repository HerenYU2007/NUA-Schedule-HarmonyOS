import { Table, Parsed, parseTable, parseGridCell } from './TimetableParser';
const LIMIT: number = 5 * 1024 * 1024;
const END: number = 0xFFFFFFFE;
const FREE: number = 0xFFFFFFFF;
function need(ok: boolean): void { if (!ok) throw new Error('XLS 文件损坏或不受支持，原课表未改变'); }
class Bytes {
  data: Uint8Array;
  view: DataView;
  constructor(data: Uint8Array) { this.data = data; this.view = new DataView(data.buffer, data.byteOffset, data.byteLength); }
  u16(p: number): number { need(p >= 0 && p + 2 <= this.data.length); return this.view.getUint16(p, true); }
  u32(p: number): number { need(p >= 0 && p + 4 <= this.data.length); return this.view.getUint32(p, true); }
}
function concat(parts: Uint8Array[], length: number): Uint8Array {
  need(length >= 0 && length <= LIMIT);
  const out = new Uint8Array(length); let at = 0;
  for (const part of parts) { const n = Math.min(part.length, length - at); out.set(part.subarray(0, n), at); at += n; if (at >= length) break; }
  need(at === length); return out;
}
class Compound {
  bytes: Bytes;
  size: number;
  fat: number[] = [];
  constructor(data: Uint8Array) {
    this.bytes = new Bytes(data);
    need(data.length >= 512 && data.length <= LIMIT);
    const magic: number[] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    magic.forEach((n: number, i: number) => need(data[i] === n));
    need(this.bytes.u16(28) === 0xFFFE && [9, 12].includes(this.bytes.u16(30)) && this.bytes.u16(32) === 6);
    this.size = Math.pow(2, this.bytes.u16(30));
    const fatSectors: number[] = [];
    for (let p = 76; p < 512; p += 4) { const n = this.bytes.u32(p); if (n !== FREE) fatSectors.push(n); }
    let next = this.bytes.u32(68); const difatCount = this.bytes.u32(72);
    need(difatCount <= 100 && this.bytes.u32(44) <= 10000);
    const seen: Set<number> = new Set<number>();
    for (let i = 0; i < difatCount; i++) {
      need(next !== END && !seen.has(next)); seen.add(next);
      const sector = new Bytes(this.sector(next));
      for (let p = 0; p < this.size - 4; p += 4) { const n = sector.u32(p); if (n !== FREE) fatSectors.push(n); }
      next = sector.u32(this.size - 4);
    }
    need(fatSectors.length === this.bytes.u32(44));
    for (const n of fatSectors) { const sector = new Bytes(this.sector(n)); for (let p = 0; p < this.size; p += 4) this.fat.push(sector.u32(p)); }
  }
  sector(id: number): Uint8Array {
    const p = (id + 1) * this.size;
    need(Number.isInteger(id) && id >= 0 && p + this.size <= this.bytes.data.length);
    return this.bytes.data.subarray(p, p + this.size);
  }
  chain(id: number, fat: number[], mini: Uint8Array | undefined = undefined, length: number = -1): Uint8Array {
    const parts: Uint8Array[] = [], seen: Set<number> = new Set<number>(); let bytes = 0;
    while (id !== END) {
      need(id < fat.length && !seen.has(id) && seen.size <= 10000); seen.add(id);
      let part: Uint8Array;
      if (mini) { need(id * 64 + 64 <= mini.length); part = mini.subarray(id * 64, id * 64 + 64); }
      else part = this.sector(id);
      bytes += part.length; need(bytes <= LIMIT); parts.push(part); id = fat[id];
    }
    return concat(parts, length < 0 ? bytes : length);
  }
  workbook(): Uint8Array {
    const directory = new Bytes(this.chain(this.bytes.u32(48), this.fat));
    let book = -1, bookLength = 0, root = -1, rootLength = 0;
    for (let p = 0; p + 128 <= directory.data.length; p += 128) {
      const nameLength = directory.u16(p + 64); if (nameLength < 2 || nameLength > 64) continue;
      let name = ''; for (let c = p; c < p + nameLength - 2; c += 2) name += String.fromCharCode(directory.u16(c));
      const type = directory.data[p + 66];
      if (type !== 2 && type !== 5) continue;
      need(directory.u32(p + 124) === 0);
      if (type === 5) { root = directory.u32(p + 116); rootLength = directory.u32(p + 120); }
      if (type === 2 && (name === 'Workbook' || name === 'Book')) {
        need(book === -1); book = directory.u32(p + 116); bookLength = directory.u32(p + 120);
      }
    }
    need(book >= 0 && bookLength > 0 && bookLength <= LIMIT);
    if (bookLength >= this.bytes.u32(56)) return this.chain(book, this.fat, undefined, bookLength);
    need(root >= 0 && rootLength > 0);
    const mini = this.chain(root, this.fat, undefined, rootLength);
    const miniBytes = new Bytes(this.chain(this.bytes.u32(60), this.fat));
    const miniFat: number[] = []; for (let p = 0; p < miniBytes.data.length; p += 4) miniFat.push(miniBytes.u32(p));
    return this.chain(book, miniFat, mini, bookLength);
  }
}
// BIFF8 CONTINUE boundaries carry an encoding flag only while character data continues.
class Chunks {
  chunks: Uint8Array[];
  index: number = 0;
  offset: number = 0;
  constructor(chunks: Uint8Array[]) { this.chunks = chunks; }
  byte(): number {
    while (this.index < this.chunks.length && this.offset >= this.chunks[this.index].length) { this.index++; this.offset = 0; }
    need(this.index < this.chunks.length);
    return this.chunks[this.index][this.offset++];
  }
  u16(): number { const a = this.byte(); return a + this.byte() * 256; }
  u32(): number { const a = this.u16(); return a + this.u16() * 65536; }
  text(): string {
    const length = this.u16(), flags = this.byte(); need(length <= 32767 && (flags & 0xF2) === 0);
    const rich = flags & 8 ? this.u16() : 0, ext = flags & 4 ? this.u32() : 0;
    need(rich <= 10000 && ext <= LIMIT);
    let wide = (flags & 1) !== 0, text = '';
    for (let i = 0; i < length; i++) {
      if (this.offset >= this.chunks[this.index].length) {
        this.index++; this.offset = 0; need(this.index < this.chunks.length);
        const continuation = this.byte(); need(continuation === 0 || continuation === 1); wide = continuation === 1;
      }
      need(this.offset + (wide ? 2 : 1) <= this.chunks[this.index].length);
      text += String.fromCharCode(wide ? this.u16() : this.byte());
    }
    for (let i = 0; i < rich * 4 + ext; i++) this.byte();
    return text;
  }
}
interface Sheet { offset: number; rows: string[][]; }
export function xlsTables(data: Uint8Array): string[][][] {
  const book = new Bytes(new Compound(data).workbook());
  const strings: string[] = [], sheets: Sheet[] = [];
  let p = 0;
  while (p + 4 <= book.data.length) {
    const id = book.u16(p), size = book.u16(p + 2), start = p + 4;
    need(start + size <= book.data.length); p = start + size;
    need(id !== 0x002F); // encrypted workbook: reject, never request credentials
    if (id === 0x0085) {
      need(size >= 8 && sheets.length < 10 && book.data[start + 5] === 0);
      sheets.push({ offset: book.u32(start), rows: [] });
    }
    if (id === 0x00FC) {
      need(strings.length === 0);
      const parts: Uint8Array[] = [book.data.subarray(start, p)];
      while (p + 4 <= book.data.length && book.u16(p) === 0x003C) {
        const n = book.u16(p + 2); need(p + 4 + n <= book.data.length);
        parts.push(book.data.subarray(p + 4, p + 4 + n)); p += 4 + n;
      }
      const chunks = new Chunks(parts); chunks.u32(); const count = chunks.u32(); need(count <= 20000);
      for (let i = 0; i < count; i++) strings.push(chunks.text());
    }
    if (id === 0x000A) break;
  }
  need(sheets.length > 0);
  for (const sheet of sheets) {
    p = sheet.offset; need(p + 4 <= book.data.length && book.u16(p) === 0x0809);
    while (p + 4 <= book.data.length) {
      const id = book.u16(p), size = book.u16(p + 2), start = p + 4;
      need(start + size <= book.data.length); p = start + size;
      if (id === 0x000A) break;
      if (id !== 0x00FD && id !== 0x0204) continue;
      need(size >= (id === 0x00FD ? 10 : 9));
      const row = book.u16(start), col = book.u16(start + 2); need(row < 5000 && col < 100);
      while (sheet.rows.length <= row) sheet.rows.push([]);
      while (sheet.rows[row].length <= col) sheet.rows[row].push('');
      let value: string;
      if (id === 0x00FD) { const index = book.u32(start + 6); need(index < strings.length); value = strings[index]; }
      else value = new Chunks([book.data.subarray(start + 6, p)]).text();
      sheet.rows[row][col] = value;
    }
  }
  return sheets.map((s: Sheet) => s.rows);
}
export function parseXls(data: Uint8Array): Parsed {
  const sheets = xlsTables(data);
  let table: Table | undefined = undefined;
  for (const rows of sheets) {
    for (let r = 0; r < Math.min(30, rows.length); r++) {
      const headers = rows[r].map((s: string) => s.replace(/\s/g, ''));
      if (headers.some((s: string) => /^(课程名称|课程名)$/.test(s)) && headers.some((s: string) => /^(实际上课时间|上课时间)$/.test(s))) {
        need(!table); table = { headers: headers, rows: rows.slice(r + 1) }; break;
      }
    }
  }
  if (table) return parseTable(table);
  need(sheets.length === 1);
  const rows = sheets[0];
  for (let r = 0; r < Math.min(30, rows.length); r++) {
    const days = rows[r].map((s: string) => {
      const text = s.replace(/\s/g, '');
      return /^(星期|周)[一二三四五六日天]$/.test(text) ? text.endsWith('天') ? 7 : '一二三四五六日'.indexOf(text.slice(-1)) + 1 : 0;
    });
    if (new Set<number>(days.filter((d: number) => d > 0)).size !== 7) continue;
    const flat: string[][] = [];
    const seen: Set<string> = new Set<string>(); let excluded = 0;
    for (const row of rows.slice(r + 1)) {
      row.forEach((value: string, col: number) => {
        if (!days[col] || !value.trim()) return;
        if (value.includes('军事技能')) { excluded++; return; }
        const key = days[col] + '|' + value; if (seen.has(key)) return; seen.add(key);
        flat.push(...parseGridCell(value, days[col]));
      });
    }
    const parsed = parseTable({ headers: ['课程名称', '实际上课时间', '实际上课教室', '授课教师'], rows: flat });
    parsed.excluded += excluded;
    parsed.warnings.push('导出周视图未提供理论/实践周次，请核对学期、节次与地点。');
    return parsed;
  }
  throw new Error('未找到可识别的课程表格');
}
