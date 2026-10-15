import { Rule } from '../model/Schedule';
import { PERIOD_START, PERIOD_END } from '../model/SchoolClock';
export interface Table { headers: string[]; rows: string[][]; warnings?: string[]; semester?: string; }
export interface Parsed { rules: Rule[]; warnings: string[]; excluded: number; }
const START: string[] = PERIOD_START;
const END: string[] = PERIOD_END;
function clean(text: string): string { return text.replace(/\u00a0/g, ' ').replace(/\s+/g, ' ').trim(); }
function split(text: string): string[] { return text.split(/[;；:：\r\n]+/).map(clean).filter((s: string) => !!s); }
function numbers(text: string): number[] {
  const found: Set<number> = new Set<number>();
  for (const part of text.trim().split(/[,，、]/)) {
    if (!/^\s*\d+(?:\s*[-—–~至]\s*\d+)?\s*$/.test(part)) throw new Error('周次无法识别');
    const range = part.trim().split(/[-—–~至]/).map((s: string) => Number(s.trim()));
    const first = range[0], last = range.length > 1 ? range[1] : first;
    if (first < 1 || last > 53 || first > last) throw new Error('周次超出范围');
    for (let n = first; n <= last; n++) found.add(n);
  }
  return Array.from(found);
}
function optionalWeeks(text: string): number[] {
  try { return numbers(text.replace(/[第周]/g, '')); } catch (_) { return []; }
}
interface Slot { weeks: number[]; day: number; first: number; last: number; }
export function parseTable(table: Table): Parsed {
  if (!Array.isArray(table.headers) || !Array.isArray(table.rows) || table.rows.length > 5000) throw new Error('课表格式无法识别');
  const col = (names: string[]): number => {
    for (const name of names) {
      const index = table.headers.findIndex((h: string) => clean(h) === name);
      if (index >= 0) return index;
    }
    return -1;
  };
  const cc = col(['课程名称', '课程名']), tc = col(['实际上课时间', '上课时间']);
  const rc = col(['实际上课教室', '上课教室', '教室', '上课地点']);
  const teacherCol = col(['授课教师', '任课教师', '教师']);
  const theoryCol = col(['理论周次']), practiceCol = col(['实践周次']);
  if (cc < 0 || tc < 0) throw new Error('没有课程名称或上课时间列');
  const result: Parsed = { rules: [], warnings: table.warnings ?? [], excluded: 0 };
  const keys: Set<string> = new Set<string>();
  for (const row of table.rows) {
    const cell = (i: number): string => i >= 0 && i < row.length ? row[i] : '';
    const course = clean(cell(cc));
    if (!course || course === '课程名称') continue;
    if (course.includes('军事技能')) { result.excluded++; continue; }
    const schedule = clean(cell(tc));
    const pattern = /第?\s*([0-9\s,，、\-—–~至]+)\s*周\s*[(（]?\s*([单双])?(?:周)?\s*[,，;；()（）\s]*(?:星期|周)\s*([一二三四五六日天1-7])\s*[,，;；(（\s]*第?\s*(\d+)\s*(?:[-—–~至]\s*(\d+))?\s*节/g;
    const slots: Slot[] = [];
    let marker: RegExpExecArray | null;
    while ((marker = pattern.exec(schedule)) !== null) {
      const weeks = numbers(marker[1]).filter((w: number) => !marker || !marker[2] || (marker[2] === '单' ? w % 2 === 1 : w % 2 === 0));
      const first = Number(marker[4]), last = Number(marker[5] || marker[4]);
      if (!weeks.length || first < 1 || last > 12 || first > last) throw new Error('节次无法识别');
      const chineseDay = '一二三四五六日'.indexOf(marker[3]);
      const day = chineseDay >= 0 ? chineseDay + 1 : marker[3] === '天' ? 7 : Number(marker[3]);
      slots.push({ weeks: weeks, day: day, first: first, last: last });
    }
    if (!slots.length || schedule.replace(pattern, '').replace(/[\s;；,，()（）单双周]+/g, '')) {
      result.warnings.push(course + '：部分时间无法确认，整行未导入'); continue;
    }
    const rooms = split(cell(rc)), teachers = split(cell(teacherCol));
    const aligned = rooms.length <= 1 || rooms.length === slots.length;
    const meetings = slots.reduce((n: number, s: Slot) => n + s.weeks.length, 0);
    const perWeek = !aligned && rooms.length === meetings;
    if (!aligned && !perWeek) result.warnings.push(course + '：教室数量不对应，地点待核对');
    const theory = optionalWeeks(cell(theoryCol)), practice = optionalWeeks(cell(practiceCol));
    let occurrence = 0;
    slots.forEach((slot: Slot, index: number) => {
      const teacher = teachers.length === slots.length ? teachers[index] : teachers.join('、');
      for (const w of slot.weeks) {
        const room = perWeek ? rooms[occurrence] : !rooms.length ? '地点待定' : rooms.length === 1 ? rooms[0] : aligned ? rooms[index] : '地点待核对';
        occurrence++;
        const practiceRoom = /校外|虚拟/.test(room) || course.includes('体育');
        const type = practice.includes(w) && theory.includes(w) ? practiceRoom ? '实践' : '理论'
          : practice.includes(w) ? '实践' : theory.includes(w) ? '理论' : practiceRoom ? '实践' : '教务同步';
        const key = [w, slot.day, slot.first, slot.last, course, room, teacher].join('|');
        if (keys.has(key)) continue;
        keys.add(key);
        result.rules.push({ from: w, to: w, day: slot.day, start: START[slot.first], end: END[slot.last],
          periods: '第' + slot.first + (slot.first === slot.last ? '' : '–' + slot.last) + '节', course: course, room: room, type: type, teacher: teacher });
      }
    });
  }
  if (!result.rules.length) throw new Error('没有识别出可导入的课程，原课表保持不变');
  if (result.rules.length > 5000) throw new Error('课表过大');
  return result;
}
export function parseGridCell(value: string, day: number): string[][] {
  const lines = value.split(/\r?\n/).map((s: string) => s.trim()).filter((s: string) => !!s && !/^[-—─]{3,}$/.test(s));
  const rows: string[][] = [];
  let start = 0, previousCourse = '', previousTeacher = '';
  const pattern = /^([0-9\s,，、\-—–~至]+)[（(]\s*\[?\s*([单双]?)周\s*\]?\s*[）)]\s*\[([0-9\s,，、\-—–至]+)节\]$/;
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(pattern);
    if (!match) continue;
    let fields = lines.slice(start, i);
    let college = -1;
    fields.forEach((s: string, index: number) => { if (s.endsWith('学院') || s === '体育部') college = index; });
    if (college >= 0) fields = fields.slice(college + 1);
    let teacher = previousTeacher, course = previousCourse;
    if (fields.length > 0) {
      if (fields.length < 2) throw new Error('课程与教师分行不完整');
      teacher = fields[fields.length - 1];
      course = fields.slice(0, -1).filter((s: string) => !/^[（(].*(?:\d+\s*班|混合班|教学班)[）)]$/.test(s)).join('');
    }
    if (!course || !teacher || i + 1 >= lines.length) throw new Error('课程、教师或地点缺失');
    const room = lines[++i];
    start = i + 1; previousCourse = course; previousTeacher = teacher;
    const periods = Array.from(new Set<number>(match[3].replace(/\s/g, '').split(/[-—–,，、]/).map((s: string) => Number(s)))).sort((a: number, b: number) => a - b);
    if (!periods.length || periods[0] < 1 || periods[periods.length - 1] > 12 || periods.some((p: number) => !Number.isInteger(p))) throw new Error('节次不受支持');
    // The export lists every actual period. Split non-contiguous runs, never fill gaps.
    let first = periods[0], last = first;
    const push = (): void => { rows.push([course, match[1] + '周' + (match[2] ? '(' + match[2] + '周)' : '') + ',周' + day + ',第' + first + (last === first ? '' : '-' + last) + '节', room, teacher]); };
    for (const p of periods.slice(1)) { if (p === last + 1) last = p; else { push(); first = p; last = p; } }
    push();
  }
  if (!rows.length || start !== lines.length) throw new Error('导出单元格未完整识别');
  return rows;
}
