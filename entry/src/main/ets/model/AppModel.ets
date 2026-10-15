import { Rule, Snapshot, courses, nowDay, dayNumber, weekday, dateText, courseStatus } from './Schedule';

import { PERIOD_START, PERIOD_END, periodSpan } from './SchoolClock';
export { PERIOD_START, PERIOD_END } from './SchoolClock';
export interface PreferencesState { theme: number; grid: boolean; reminders: boolean; minutes: number; debug?: boolean; reminderMode?: number; selectedOnly?: boolean; selectedCourses?: string[]; }
export interface ReminderOverride { key: string; mode: number; minutes: number; }
export interface AgendaEvent {
  id: string; title: string; place: string; date: string; start: string; end: string;
  allDay: boolean; done: boolean; remind: boolean;
}
export interface AppState { schema: number; preferences: PreferencesState; events: AgendaEvent[]; overrides?: ReminderOverride[]; }
export interface Meeting { rule: Rule; day: number; key: string; }
export interface TimelineItem { id: string; title: string; place: string; time: string; order: string; done: boolean; meeting?: Meeting; event?: AgendaEvent; }
export interface GridBlock { meeting: Meeting; first: number; last: number; lane: number; lanes: number; }
export interface ReminderPlan { key: string; title: string; content: string; at: number; mode?: number; }
export function defaultState(): AppState { return { schema: 1, preferences: { theme: 0, grid: false, reminders: false, minutes: 15, debug: false, reminderMode: 1, selectedOnly: false, selectedCourses: [] }, events: [], overrides: [] }; }
export function validState(value: AppState): AppState {
  if (!value || value.schema !== 1 || !value.preferences || !Array.isArray(value.events) || value.events.length > 2000) throw new Error('设置格式错误');
  const p = value.preferences;
  if (![0, 1, 2].includes(p.theme) || typeof p.grid !== 'boolean' || typeof p.reminders !== 'boolean' || ![5, 10, 15, 20, 30].includes(p.minutes)) throw new Error('偏好无效');
  if (p.debug === undefined) p.debug = false; if (p.reminderMode === undefined) p.reminderMode = 1;
  if (p.selectedOnly === undefined) p.selectedOnly = false; if (p.selectedCourses === undefined) p.selectedCourses = [];
  if (typeof p.debug !== 'boolean' || ![0, 1, 2].includes(p.reminderMode) || typeof p.selectedOnly !== 'boolean' || !Array.isArray(p.selectedCourses) || p.selectedCourses.some((s: string) => typeof s !== 'string' || s.length > 120) || p.selectedCourses.length > 5000) throw new Error('提醒设置无效');
  if (value.overrides === undefined) value.overrides = [];
  if (!Array.isArray(value.overrides) || value.overrides.length > 10000) throw new Error('单独提醒过多');
  const overrideIds: Set<string> = new Set<string>();
  for (const item of value.overrides) { if (!item || typeof item.key !== 'string' || !item.key || item.key.length > 250 || overrideIds.has(item.key) || ![0, 1, 2].includes(item.mode) || !Number.isInteger(item.minutes) || item.minutes < 0 || item.minutes > 120) throw new Error('单独提醒无效'); overrideIds.add(item.key); }
  const ids: Set<string> = new Set<string>();
  for (const event of value.events) { validEvent(event); if (ids.has(event.id)) throw new Error('重复日程'); ids.add(event.id); }
  return value;
}
export function validEvent(event: AgendaEvent): AgendaEvent {
  if (!event || typeof event.id !== 'string' || !event.id || event.id.length > 100 || typeof event.title !== 'string' || !event.title.trim() || event.title.length > 80 || typeof event.place !== 'string' || event.place.length > 200) throw new Error('请填写标题（最多80字）并检查地点');
  dayNumber(event.date);
  if (typeof event.allDay !== 'boolean' || typeof event.done !== 'boolean' || typeof event.remind !== 'boolean' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(event.start) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(event.end) || (!event.allDay && event.start >= event.end)) throw new Error('结束时间须晚于开始时间，暂不支持跨日');
  return event;
}
export function monday(day: number): number { return day - weekday(day) + 1; }
export function meetings(snapshot: Snapshot, first: number, days: number = 7): Meeting[] {
  const result: Meeting[] = [];
  for (let day = first; day < first + days; day++) courses(snapshot, day).forEach((r: Rule, index: number) => result.push({ rule: r, day: day, key: dateText(day) + '|' + (r.id || String(index) + ':' + r.course + ':' + r.start) }));
  return result;
}
export function agenda(snapshot: Snapshot, state: AppState, day: number, now: number): TimelineItem[] {
  const result = meetings(snapshot, day, 1).map((m: Meeting): TimelineItem => ({ id: m.key, title: m.rule.course, place: m.rule.room + ' · ' + m.rule.periods, time: m.rule.start + '\n' + m.rule.end, order: m.rule.start, done: courseStatus(m.rule, day, now) === '已结束', meeting: m }));
  state.events.filter((e: AgendaEvent) => e.date === dateText(day)).forEach((e: AgendaEvent) => result.push({ id: e.id, title: e.title, place: e.place + (e.remind ? ' · 提醒' : ''), time: e.allDay ? '全天' : e.start + '\n' + e.end, order: e.allDay ? '00:00' : e.start, done: e.done, event: e }));
  return result.sort((a: TimelineItem, b: TimelineItem) => a.order.localeCompare(b.order));
}
export function countdown(snapshot: Snapshot, now: number): string {
  const first = meetings(snapshot, nowDay(now), 8).find((m: Meeting) => epoch(m.day, m.rule.end) > now);
  if (!first) return '';
  if (epoch(first.day, first.rule.start) <= now) return first.rule.course + ' · 正在上课 · 距下课 ' + Math.ceil((epoch(first.day, first.rule.end) - now) / 60000) + ' 分钟';
  const gap = Math.ceil((epoch(first.day, first.rule.start) - now) / 60000);
  return first.rule.course + ' · 距上课 ' + (gap >= 60 ? Math.floor(gap / 60) + ' 小时 ' : '') + gap % 60 + ' 分钟';
}
export function epoch(day: number, time: string): number { return day * 86400000 - 8 * 3600000 + (Number(time.slice(0, 2)) * 60 + Number(time.slice(3))) * 60000; }
export function span(rule: Rule): number[] {
  return periodSpan(rule);
}
export function gridBlocks(snapshot: Snapshot, first: number): GridBlock[] {
  const result: GridBlock[] = [];
  for (let day = first; day < first + 7; day++) {
    const daily = meetings(snapshot, day, 1).filter((m: Meeting) => span(m.rule).length > 0).sort((a: Meeting, b: Meeting) => span(a.rule)[0] - span(b.rule)[0]);
    for (let i = 0; i < daily.length;) {
      let end = i + 1, last = span(daily[i].rule)[1];
      while (end < daily.length && span(daily[end].rule)[0] <= last) { last = Math.max(last, span(daily[end].rule)[1]); end++; }
      for (let j = i; j < end; j++) { const s = span(daily[j].rule); result.push({ meeting: daily[j], first: s[0], last: s[1], lane: j - i, lanes: end - i }); }
      i = end;
    }
  }
  return result;
}
export function courseColor(name: string, dark: boolean): string {
  const light: string[] = ['#8BCAE8', '#F2B7C7', '#99D6D1', '#C4B4F0', '#EAC28B', '#AABFEF', '#ECA891'];
  const night: string[] = ['#275775', '#704153', '#255D59', '#514270', '#695333', '#394D78', '#724838'];
  let hash = 0; for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) | 0;
  return (dark ? night : light)[((hash % 7) + 7) % 7];
}
export function reminderPlans(snapshot: Snapshot, state: AppState, now: number): ReminderPlan[] {
  const result: ReminderPlan[] = [];
  if (state.preferences.reminders) for (const m of meetings(snapshot, nowDay(now), 371)) {
    const setting = effectiveReminder(state, m); if (setting.mode === 0) continue;
    const at = epoch(m.day, m.rule.start) - setting.minutes * 60000;
    if (at > now) result.push({ key: m.key, title: '即将上课 · ' + m.rule.course, content: m.rule.start + '–' + m.rule.end + ' · ' + m.rule.room, at: at, mode: setting.mode });
  }
  for (const e of state.events) if (e.remind && !e.done) {
    const at = epoch(dayNumber(e.date), e.allDay ? '09:00' : e.start) - (e.allDay ? 0 : 15 * 60000);
    if (at > now) result.push({ key: e.id, title: '日程提醒 · ' + e.title, content: e.place || (e.allDay ? '全天' : e.start + '–' + e.end), at: at });
  }
  return result.sort((a: ReminderPlan, b: ReminderPlan) => a.at - b.at).slice(0, 30);
}
export function reminderKey(meeting: Meeting, single: boolean): string { return single ? 'lesson:' + meeting.key : 'course:' + meeting.rule.course; }
export function effectiveReminder(state: AppState, meeting: Meeting): ReminderOverride {
  const fallback: ReminderOverride = { key: '', mode: state.preferences.reminderMode ?? 1, minutes: state.preferences.minutes };
  if (!state.preferences.reminders) { fallback.mode = 0; return fallback; }
  const overrides = state.overrides || [];
  const own = overrides.find((r: ReminderOverride) => r.key === reminderKey(meeting, true)) || overrides.find((r: ReminderOverride) => r.key === reminderKey(meeting, false));
  if (own) return own;
  if (state.preferences.selectedOnly && !(state.preferences.selectedCourses || []).includes(meeting.rule.course)) fallback.mode = 0;
  return fallback;
}
