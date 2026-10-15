import { normalizeClock } from './SchoolClock';
export interface Rule {
  id?: string;
  color?: number;
  credits?: string;
  note?: string;
  from: number;
  to: number;
  day: number;
  start: string;
  end: string;
  periods: string;
  course: string;
  room: string;
  type: string;
  teacher: string;
}
export interface Snapshot {
  schema: number;
  startDate: string;
  rules: Rule[];
  syncedAt: number;
}
export interface CardData {
  title: string;
  subtitle: string;
  lines: CardLine[];
  empty: string;
  overflow: string;
  next?: string;
  availableHeight?: number;
}
export interface CardLine {
  time: string;
  course: string;
  room: string;
  status: string;
}
const DAY: number = 86400000;
export function dayNumber(date: string): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error('日期格式错误');
  const parts = date.split('-').map((v: string) => Number(v));
  const n = Date.UTC(parts[0], parts[1] - 1, parts[2]) / DAY;
  if (dateText(n) !== date) throw new Error('日期不存在');
  return n;
}
export function dateText(day: number): string { return new Date(day * DAY).toISOString().slice(0, 10); }
export function nowDay(now: number = Date.now()): number { return Math.floor((now + 8 * 3600000) / DAY); }
export function minuteOfDay(now: number = Date.now()): number { return Math.floor((now + 8 * 3600000) % DAY / 60000); }
export function formEpoch(now: number = Date.now()): string { return dateText(nowDay(now)) + (minuteOfDay(now) >= 1320 ? ':late' : ':day'); }
export function weekday(day: number): number { return ((day + 3) % 7 + 7) % 7 + 1; }
export function week(day: number, startDate: string): number {
  const start = dayNumber(startDate);
  return Math.floor((day - (start - weekday(start) + 1)) / 7) + 1;
}
function minutes(time: string): number { return Number(time.slice(0, 2)) * 60 + Number(time.slice(3)); }
export function courseStatus(rule: Rule, day: number, now: number = Date.now()): string {
  if (day < nowDay(now)) return '已结束';
  if (day > nowDay(now)) return '未开始';
  const minute = minuteOfDay(now);
  return minute >= minutes(rule.end) ? '已结束' : minute >= minutes(rule.start) ? '正在进行' : '未开始';
}
export function courses(snapshot: Snapshot, day: number): Rule[] {
  const w = week(day, snapshot.startDate);
  return snapshot.rules.filter((r: Rule) => r.day === weekday(day) && r.from <= w && r.to >= w)
    .sort((a: Rule, b: Rule) => a.start.localeCompare(b.start) || a.course.localeCompare(b.course));
}
export function cardData(snapshot: Snapshot, offset: number = -1, now: number = Date.now(), capacity: number = 3): CardData {
  const selected = offset < 0 ? (minuteOfDay(now) >= 1320 ? 1 : 0) : offset;
  const day = nowDay(now) + selected;
  const all = courses(snapshot, day);
  const visible = all.filter((r: Rule) => courseStatus(r, day, now) !== '已结束');
  return {
    title: (selected === 0 ? '今天' : '明天') + ' · ' + dateText(day).slice(5).replace('-', '/'),
    subtitle: '星期' + '一二三四五六日'.charAt(weekday(day) - 1) + ' · 第' + week(day, snapshot.startDate) + '周',
    lines: visible.slice(0, capacity).map((r: Rule): CardLine => ({
      time: r.start + '–' + r.end, course: r.course, room: r.room,
      status: courseStatus(r, day, now)
    })),
    empty: snapshot.rules.length === 0 ? '尚未导入课表，点此打开应用' : all.length > 0 ? '今日课程已全部结束' : '当天没有课程',
    overflow: visible.length > capacity ? '还有' + (visible.length - capacity) + '节课 · 点此查看' : ''
  };
}
export function validSnapshot(value: Snapshot): Snapshot {
  if (!value || typeof value.startDate !== 'string') throw new Error('课表格式错误');
  dayNumber(value.startDate);
  const year = Number(value.startDate.slice(0, 4)); if (year < 1900 || year > 2200) throw new Error('开学日期不受支持');
  if (!Number.isFinite(value.syncedAt) || value.syncedAt < 0) throw new Error('同步日期无效');
  if (value.schema !== 1 || !Array.isArray(value.rules) || value.rules.length > 5000) throw new Error('课表数据不受支持');
  const ids: Set<string> = new Set<string>();
  for (let index = 0; index < value.rules.length; index++) {
    const r = value.rules[index];
    if (!Number.isInteger(r.from) || !Number.isInteger(r.to) || r.from < 1 || r.to > 53 || r.from > r.to
      || !Number.isInteger(r.day) || r.day < 1 || r.day > 7 || typeof r.course !== 'string' || !r.course.trim()
      || typeof r.room !== 'string' || typeof r.teacher !== 'string' || typeof r.type !== 'string'
      || r.course.length > 120 || r.room.length > 300 || r.teacher.length > 400
      || typeof r.periods !== 'string' || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(r.start)
      || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(r.end) || r.start >= r.end) throw new Error('课程字段不完整');
    normalizeClock(r);
    if (r.id === undefined) r.id = stableId(r, index);
    if (typeof r.id !== 'string' || !/^[A-Za-z0-9._-]{1,100}$/.test(r.id) || ids.has(r.id)) throw new Error('课程编号无效或重复');
    ids.add(r.id);
    if (r.color === undefined) r.color = 0; if (r.credits === undefined) r.credits = ''; if (r.note === undefined) r.note = '';
    if (!Number.isInteger(r.color) || r.color < -2147483648 || r.color > 4294967295 || typeof r.credits !== 'string' || r.credits.length > 40 || typeof r.note !== 'string' || r.note.length > 2000) throw new Error('课程详细字段无效');
  }
  return value;
}
export function stableId(rule: Rule, index: number): string {
  const value = [rule.course, rule.from, rule.to, rule.day, rule.start, rule.end, rule.room, rule.teacher, index].join('|');
  let hash = 2166136261; for (let i = 0; i < value.length; i++) hash = Math.imul(hash ^ value.charCodeAt(i), 16777619);
  return 'legacy-' + (hash >>> 0).toString(16) + '-' + index;
}
export function copyRule(rule: Rule): Rule { return { id: rule.id, color: rule.color ?? 0, credits: rule.credits ?? '', note: rule.note ?? '', from: rule.from, to: rule.to, day: rule.day, start: rule.start, end: rule.end, periods: rule.periods, course: rule.course, room: rule.room, teacher: rule.teacher, type: rule.type }; }
