import { Rule, Snapshot, copyRule, validSnapshot, dayNumber, dateText } from './Schedule';
import { AppState, AgendaEvent, ReminderOverride, validState, monday, epoch } from './AppModel';
export interface Backup { format: string; schema: number; startDate: string; rules: Rule[]; harmonyState?: AppState; }
export interface Restored { snapshot: Snapshot; app?: AppState; }
function cleanState(state: AppState): AppState {
  validState(state);
  return { schema: 1, preferences: { theme: state.preferences.theme, grid: state.preferences.grid, reminders: state.preferences.reminders, minutes: state.preferences.minutes, debug: state.preferences.debug, reminderMode: state.preferences.reminderMode, selectedOnly: state.preferences.selectedOnly, selectedCourses: (state.preferences.selectedCourses || []).slice() },
    events: state.events.map((e: AgendaEvent): AgendaEvent => ({ id: e.id, title: e.title, place: e.place, date: e.date, start: e.start, end: e.end, allDay: e.allDay, done: e.done, remind: e.remind })), overrides: (state.overrides || []).map((r: ReminderOverride): ReminderOverride => ({ key: r.key, mode: r.mode, minutes: r.minutes })) };
}
export function backupText(snapshot: Snapshot, app: AppState): string {
  validSnapshot(snapshot);
  const value: Backup = { format: 'nua-schedule-backup', schema: 1, startDate: snapshot.startDate, rules: snapshot.rules.map(copyRule), harmonyState: cleanState(app) };
  return JSON.stringify(value, null, 2);
}
export function parseBackup(text: string): Restored {
  if (text.length > 4 * 1024 * 1024) throw new Error('备份超过4MB');
  const value = JSON.parse(text) as Backup;
  if (!value || value.format !== 'nua-schedule-backup' || value.schema !== 1 || !Array.isArray(value.rules)) throw new Error('不是受支持的课表备份');
  const source: Snapshot = { schema: 1, startDate: value.startDate, rules: value.rules, syncedAt: Date.now() }; validSnapshot(source);
  const snapshot: Snapshot = { schema: 1, startDate: source.startDate, rules: source.rules.map(copyRule), syncedAt: source.syncedAt };
  return { snapshot: snapshot, app: value.harmonyState ? cleanState(value.harmonyState) : undefined };
}
function escapeText(value: string): string { return value.replace(/\\/g, '\\\\').replace(/\r\n|\r|\n/g, '\\n').replace(/;/g, '\\;').replace(/,/g, '\\,'); }
function fold(value: string): string {
  let line = '', size = 0;
  for (const character of Array.from(value)) { const code = character.codePointAt(0) || 0, bytes = code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4; if (size + bytes > 75) { line += '\r\n '; size = 1; } line += character; size += bytes; }
  return line + '\r\n';
}
function utc(at: number): string { return new Date(at).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z'); }
export function calendarText(snapshot: Snapshot): string {
  validSnapshot(snapshot); const total = snapshot.rules.reduce((sum: number, r: Rule) => sum + r.to - r.from + 1, 0); if (total > 10000) throw new Error('上课次数超过10000，请分学期导出');
  let out = fold('BEGIN:VCALENDAR') + fold('VERSION:2.0') + fold('PRODID:-//NUA Schedule//HarmonyOS//ZH-CN') + fold('CALSCALE:GREGORIAN');
  const first = monday(dayNumber(snapshot.startDate)), stamp = utc(Date.now());
  for (const rule of snapshot.rules) for (let w = rule.from; w <= rule.to; w++) {
    const day = first + (w - 1) * 7 + rule.day - 1;
    out += fold('BEGIN:VEVENT') + fold('UID:' + rule.id + '-' + dateText(day) + '@nua-schedule.local') + fold('DTSTAMP:' + stamp) + fold('DTSTART:' + utc(epoch(day, rule.start))) + fold('DTEND:' + utc(epoch(day, rule.end))) + fold('SUMMARY:' + escapeText(rule.course)) + fold('LOCATION:' + escapeText(rule.room)) + fold('DESCRIPTION:' + escapeText(rule.periods + ' · 教师：' + rule.teacher + '\n' + (rule.note || ''))) + fold('END:VEVENT');
  }
  return out + fold('END:VCALENDAR');
}
function u16(value: number): number[] { return [value & 255, (value >>> 8) & 255]; }
function u32(value: number): number[] { return [value & 255, (value >>> 8) & 255, (value >>> 16) & 255, (value >>> 24) & 255]; }
function utf16(value: string): number[] { const bytes: number[] = []; for (let i = 0; i < value.length; i++) bytes.push(...u16(value.charCodeAt(i))); return bytes; }
function record(id: number, bytes: number[]): Uint8Array { if (bytes.length > 8224) throw new Error('单元格内容过长'); return new Uint8Array(u16(id).concat(u16(bytes.length), bytes)); }
function joined(chunks: Uint8Array[]): Uint8Array { const result = new Uint8Array(chunks.reduce((sum: number, b: Uint8Array) => sum + b.length, 0)); let offset = 0; for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; } return result; }
function bof(kind: number): Uint8Array { return record(0x0809, u16(0x0600).concat(u16(kind), u16(0x0DBB), u16(0x07CC), u32(0x41), u32(6))); }
function font(bold: boolean): Uint8Array { return record(0x0031, u16(220).concat(u16(0), u16(0x7FFF), u16(bold ? 700 : 400), u16(0), [0, 0, 0, 0, 5, 0, 65, 114, 105, 97, 108])); }
function xf(fontIndex: number): Uint8Array { return record(0x00E0, u16(fontIndex).concat(u16(0), u16(0), [8, 0, 0, 0], new Array<number>(10).fill(0))); }
function bound(offset: number): Uint8Array { const name = '课程安排'; return record(0x0085, u32(offset).concat([0, 0, name.length, 1], utf16(name))); }
function label(row: number, col: number, value: string, header: boolean = false): Uint8Array { return record(0x0204, u16(row).concat(u16(col), u16(header ? 1 : 0), u16(value.length), [1], utf16(value))); }
export function spreadsheetBytes(snapshot: Snapshot): Uint8Array {
  validSnapshot(snapshot);
  const head = ['课程名称', '开始周', '结束周', '星期', '节次', '开始时间', '结束时间', '地点', '教师', '学分', '备注'];
  const cells: Uint8Array[] = []; head.forEach((s: string, i: number) => cells.push(label(0, i, s, true)));
  snapshot.rules.forEach((r: Rule, i: number) => {
    const values = [r.course, String(r.from), String(r.to), '周' + '一二三四五六日'.charAt(r.day - 1), r.periods, r.start, r.end, r.room, r.teacher, r.credits || '', r.note || ''];
    values.forEach((value: string, col: number) => cells.push(label(i + 1, col, value)));
  });
  cells.push(label(snapshot.rules.length + 2, 0, '开学日期：' + snapshot.startDate + '；该日所在周为第1周。恢复本应用请使用JSON备份。'));
  const eof = record(0x000A, []), global = [bof(5), font(false), font(true), xf(0), xf(1), bound(0), eof];
  const globalSize = global.reduce((sum: number, b: Uint8Array) => sum + b.length, 0); global[5] = bound(globalSize);
  const dimensions = record(0x0200, u32(0).concat(u32(snapshot.rules.length + 3), u16(0), u16(11), u16(0)));
  const widths: Uint8Array[] = []; for (let col = 0; col < head.length; col++) widths.push(record(0x007D, u16(col).concat(u16(col), u16((col === 0 || col === 10 ? 28 : col === 7 ? 18 : 12) * 256), u16(0), u16(0), u16(0))));
  const book = joined(global.concat([bof(0x0010), dimensions], widths, cells, [eof]));
  if (book.length > 4 * 1024 * 1024) throw new Error('表格超过4MB');
  return compound(book);
}
function compound(book: Uint8Array): Uint8Array {
  const streamSize = Math.max(4096, book.length), sectors = Math.ceil(streamSize / 512); let fatCount = 1;
  while (fatCount < Math.ceil((sectors + 1 + fatCount) / 128)) fatCount++;
  if (fatCount > 109) throw new Error('表格过大');
  const total = sectors + 1 + fatCount, bytes = new Uint8Array((total + 1) * 512), view = new DataView(bytes.buffer);
  bytes.set(new Uint8Array([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]));
  view.setUint16(24, 0x003E, true); view.setUint16(26, 3, true); view.setUint16(28, 0xFFFE, true); view.setUint16(30, 9, true); view.setUint16(32, 6, true);
  view.setUint32(44, fatCount, true); view.setUint32(48, sectors, true); view.setUint32(56, 4096, true); view.setUint32(60, 0xFFFFFFFE, true); view.setUint32(68, 0xFFFFFFFE, true);
  bytes.fill(255, 76, 512); for (let f = 0; f < fatCount; f++) view.setUint32(76 + f * 4, sectors + 1 + f, true);
  bytes.set(book, 512); const directory = (sectors + 1) * 512;
  for (let entry = 0; entry < 2; entry++) {
    const p = directory + entry * 128, name = entry === 0 ? 'Root Entry' : 'Workbook'; bytes.set(new Uint8Array(utf16(name + '\0')), p); view.setUint16(p + 64, (name.length + 1) * 2, true); bytes[p + 66] = entry === 0 ? 5 : 2; bytes[p + 67] = 1;
    view.setUint32(p + 68, 0xFFFFFFFF, true); view.setUint32(p + 72, 0xFFFFFFFF, true); view.setUint32(p + 76, entry === 0 ? 1 : 0xFFFFFFFF, true); view.setUint32(p + 116, entry === 0 ? 0xFFFFFFFE : 0, true); view.setUint32(p + 120, entry === 0 ? 0 : streamSize, true);
  }
  const fatOffset = (sectors + 2) * 512; bytes.fill(255, fatOffset);
  for (let sector = 0; sector < sectors; sector++) view.setUint32(fatOffset + sector * 4, sector + 1 === sectors ? 0xFFFFFFFE : sector + 1, true);
  view.setUint32(fatOffset + sectors * 4, 0xFFFFFFFE, true); for (let f = 0; f < fatCount; f++) view.setUint32(fatOffset + (sectors + 1 + f) * 4, 0xFFFFFFFD, true);
  return bytes;
}
