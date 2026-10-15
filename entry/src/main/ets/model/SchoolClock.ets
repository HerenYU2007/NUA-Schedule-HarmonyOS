import { Rule } from './Schedule';
export const DEFAULT_START: string[] = ['', '08:00', '08:55', '10:00', '10:55', '14:00', '14:55', '16:00', '16:50', '18:30', '19:20', '20:30', '21:15'];
export const DEFAULT_END: string[] = ['', '08:45', '09:40', '10:45', '11:40', '14:45', '15:40', '16:45', '17:40', '19:20', '20:10', '21:15', '22:00'];
// Keep array identity: all consumers (including cards) share the active clock.
export const PERIOD_START: string[] = DEFAULT_START.slice();
export const PERIOD_END: string[] = DEFAULT_END.slice();
export interface PeriodClock { starts: string[]; ends: string[]; }
export function defaultClock(): PeriodClock { return { starts: DEFAULT_START.slice(), ends: DEFAULT_END.slice() }; }
export function currentClock(): PeriodClock { return { starts: PERIOD_START.slice(), ends: PERIOD_END.slice() }; }
export function validClock(value: PeriodClock): PeriodClock {
  if (!value || !Array.isArray(value.starts) || !Array.isArray(value.ends) || value.starts.length !== 13 || value.ends.length !== 13) throw new Error('需要完整的12节时间');
  for (let p = 1; p <= 12; p++) {
    if (typeof value.starts[p] !== 'string' || typeof value.ends[p] !== 'string' || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value.starts[p]) || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value.ends[p]) || value.starts[p] >= value.ends[p]) throw new Error('第' + p + '节结束时间须晚于开始时间');
    if (p > 1 && value.ends[p - 1] > value.starts[p]) throw new Error('第' + (p - 1) + '节与第' + p + '节时间重叠');
  }
  return value;
}
export function useClock(value: PeriodClock): void { validClock(value); for (let p = 1; p <= 12; p++) { PERIOD_START[p] = value.starts[p]; PERIOD_END[p] = value.ends[p]; } }
export function periodSpan(rule: Rule): number[] {
  const label = rule.periods.match(/^第?\s*(\d{1,2})(?:\s*[-—–~至]\s*(\d{1,2}))?\s*节$/);
  if (label) { const first = Number(label[1]), last = Number(label[2] || label[1]); if (first >= 1 && last <= 12 && last >= first) return [first, last]; }
  const first = PERIOD_START.indexOf(rule.start), last = PERIOD_END.indexOf(rule.end);
  return first > 0 && last >= first ? [first, last] : [];
}
export function normalizeClock(rule: Rule): void {
  if (!/^第?\s*\d{1,2}(?:\s*[-—–~至]\s*\d{1,2})?\s*节$/.test(rule.periods)) return;
  const span = periodSpan(rule); if (!span.length) return;
  const first = span[0], last = span[1];
  const oldStart = first === 2 ? '08:50' : first === 4 ? '10:50' : first === 6 ? '14:50' : DEFAULT_START[first];
  const oldEnd = last === 1 ? '08:50' : last === 3 ? '10:50' : last === 5 ? '14:50' : last === 7 ? '16:50' : DEFAULT_END[last];
  if (rule.clockBound === undefined) rule.clockBound = (rule.start === oldStart && rule.end === oldEnd) || (rule.start === DEFAULT_START[first] && rule.end === DEFAULT_END[last]) || (rule.start === PERIOD_START[first] && rule.end === PERIOD_END[last]);
  if (rule.clockBound) { rule.start = PERIOD_START[first]; rule.end = PERIOD_END[last]; }
}
export function minute(time: string): number { return Number(time.slice(0, 2)) * 60 + Number(time.slice(3)); }
