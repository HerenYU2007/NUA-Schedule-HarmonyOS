import { Rule } from './Schedule';
export const PERIOD_START: string[] = ['', '08:00', '08:55', '10:00', '10:55', '14:00', '14:50', '16:00', '16:50', '18:30', '19:20', '20:30', '21:15'];
export const PERIOD_END: string[] = ['', '08:45', '09:40', '10:45', '11:40', '14:50', '15:40', '16:50', '17:40', '19:20', '20:10', '21:15', '22:00'];
export function periodSpan(rule: Rule): number[] {
  const label = rule.periods.match(/^第?\s*(\d{1,2})(?:\s*[-—–~至]\s*(\d{1,2}))?\s*节$/);
  if (label) { const first = Number(label[1]), last = Number(label[2] || label[1]); if (first >= 1 && last <= 12 && last >= first) return [first, last]; }
  const first = PERIOD_START.indexOf(rule.start), last = PERIOD_END.indexOf(rule.end);
  return first > 0 && last >= first ? [first, last] : [];
}
export function normalizeClock(rule: Rule): void {
  const span = periodSpan(rule); if (!span.length) return;
  const first = span[0], last = span[1];
  const oldStart = first === 2 ? '08:50' : first === 4 ? '10:50' : PERIOD_START[first];
  const oldEnd = last === 1 ? '08:50' : last === 3 ? '10:50' : PERIOD_END[last];
  if (rule.start === oldStart && rule.end === oldEnd) { rule.start = PERIOD_START[first]; rule.end = PERIOD_END[last]; }
}
export function minute(time: string): number { return Number(time.slice(0, 2)) * 60 + Number(time.slice(3)); }
