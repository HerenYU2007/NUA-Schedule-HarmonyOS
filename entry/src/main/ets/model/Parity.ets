import { Rule, Snapshot, copyRule, dateText, dayNumber, weekday, week, courses, validSnapshot } from './Schedule';
import { AppState, AgendaEvent, Meeting, TimelineItem, meetings, monday, agenda, span } from './AppModel';
import { PERIOD_START, PERIOD_END, minute } from './SchoolClock';
export interface CourseDraft { weeks: string; day: number; first: number; last: number; custom: boolean; start: string; end: string; room: string; teacher: string; }
export interface BoardBlock { id: string; day: number; first: number; last: number; meetings: Meeting[]; event?: AgendaEvent; conflicts: number; }
export interface WeekPage { day: number; key: string; meetings: Meeting[]; events: AgendaEvent[]; blocks: BoardBlock[]; outside: TimelineItem[]; }
export interface ChangeLine { kind: string; text: string; }
export function parseWeeks(text: string): number[] {
  const result: Set<number> = new Set<number>();
  const clean = text.replace(/[第周\s]/g, '').replace(/[，、；;]/g, ',').replace(/[—–~至]/g, '-');
  for (const piece of clean.split(',')) {
    const match = piece.match(/^(\d{1,2})(?:-(\d{1,2}))?([单双])?$/); if (!match) throw new Error('周数示例：1-16、1-16单、1-8,10-16');
    const first = Number(match[1]), last = Number(match[2] || match[1]); if (first < 1 || last > 53 || first > last) throw new Error('周数须在1—53之间');
    for (let w = first; w <= last; w++) if (!match[3] || (w % 2 === (match[3] === '单' ? 1 : 0))) result.add(w);
  }
  const values = Array.from(result).sort((a: number, b: number) => a - b); if (!values.length) throw new Error('请选择至少一周'); return values;
}
export function slotRules(snapshot: Snapshot, selected: Meeting): Rule[] {
  return snapshot.rules.filter((r: Rule) => r.course === selected.rule.course && r.day === selected.rule.day && r.start === selected.rule.start && r.end === selected.rule.end && r.room === selected.rule.room && r.teacher === selected.rule.teacher);
}
export function draftFor(snapshot: Snapshot, selected: Meeting): CourseDraft {
  const rules = slotRules(snapshot, selected), weeks: Set<number> = new Set<number>();
  for (const r of rules) for (let w = r.from; w <= r.to; w++) weeks.add(w);
  const range = span(selected.rule);
  return { weeks: Array.from(weeks).sort((a: number, b: number) => a - b).join(','), day: selected.rule.day, first: range[0] || 1, last: range[1] || 2, custom: !range.length, start: selected.rule.start, end: selected.rule.end, room: selected.rule.room, teacher: selected.rule.teacher };
}
export function newDraft(snapshot: Snapshot, day: number, first: number = 1, last: number = 2): CourseDraft {
  const w = week(day, snapshot.startDate); if (w < 1 || w > 53) throw new Error('请先设置开学时间，新增课程需在第1—53周');
  return { weeks: String(w), day: weekday(day), first: first, last: last, custom: false, start: PERIOD_START[first], end: PERIOD_END[last], room: '', teacher: '' };
}
export function mergeSlots(snapshot: Snapshot, ids: string[], edits: Rule[]): Snapshot {
  const present = new Set<string>(snapshot.rules.map((r: Rule) => r.id || '')); if (ids.some((id: string) => !present.has(id))) throw new Error('原时段已变化，请返回重新编辑');
  const next: Snapshot = { schema: 1, startDate: snapshot.startDate, syncedAt: snapshot.syncedAt, rules: snapshot.rules.filter((r: Rule) => !ids.includes(r.id || '')).map(copyRule).concat(edits.map(copyRule)) };
  return validSnapshot(next);
}
export function draftsToRules(slots: CourseDraft[], course: string, color: number, credits: string, note: string, originals: Rule[], nonce: string): Rule[] {
  if (!course.trim() || !slots.length) throw new Error('请填写课程名称并保留至少一个时段');
  const result: Rule[] = [], used: Set<string> = new Set<string>();
  slots.forEach((slot: CourseDraft, index: number) => {
    if (!Number.isInteger(slot.day) || slot.day < 1 || slot.day > 7 || slot.first < 1 || slot.last > 12 || slot.last < slot.first) throw new Error('星期或节次无效');
    const start = slot.custom ? slot.start : PERIOD_START[slot.first], end = slot.custom ? slot.end : PERIOD_END[slot.last];
    for (const w of parseWeeks(slot.weeks)) {
      const original = index === 0 ? originals.find((r: Rule) => r.from <= w && r.to >= w && !used.has(r.id || '')) : undefined;
      const id = original?.id || nonce + '-' + index + '-' + w; used.add(id);
      result.push({ id: id, color: color, credits: credits, note: note, course: course.trim(), from: w, to: w, day: slot.day, start: start, end: end, periods: slot.custom ? '' : '第' + slot.first + (slot.last === slot.first ? '' : '—' + slot.last) + '节', room: slot.room.trim(), teacher: slot.teacher.trim(), type: original?.type || originals[0]?.type || '自定义' });
    }
  });
  return result;
}
export function overlaps(start: string, end: string, otherStart: string, otherEnd: string): boolean { return start < otherEnd && otherStart < end; }
export function freeCell(snapshot: Snapshot, state: AppState, day: number, first: number, last: number): boolean {
  if (first < 1 || last > 12 || first > last) return false;
  const start = PERIOD_START[first], end = PERIOD_END[last];
  return !courses(snapshot, day).some((r: Rule) => overlaps(start, end, r.start, r.end)) && !state.events.some((e: AgendaEvent) => !e.done && !e.allDay && e.date === dateText(day) && overlaps(start, end, e.start, e.end));
}
export function dragSpan(first: number, last: number, delta: number, edge: number): number[] {
  if (edge < 0) return [Math.max(1, Math.min(last, first + delta)), last];
  if (edge > 0) return [first, Math.min(12, Math.max(first, last + delta))];
  const shift = Math.max(1 - first, Math.min(12 - last, delta)); return [first + shift, last + shift];
}
function projected(time: string, end: boolean): number {
  const value = minute(time);
  for (let period = 1; period <= 12; period++) {
    const start = minute(PERIOD_START[period]), finish = minute(PERIOD_END[period]);
    if (value >= start && value <= finish) return period - 1 + (value - start) / (finish - start);
    if (period < 12 && value > finish && value < minute(PERIOD_START[period + 1])) return end ? period : period;
  }
  return -1;
}
export function agendaSpan(event: AgendaEvent): number[] {
  if (event.allDay || event.done) return [];
  const first = projected(event.start, false), last = projected(event.end, true);
  return first >= 0 && last > first && minute(event.start) >= minute(PERIOD_START[1]) && minute(event.end) <= minute(PERIOD_END[12]) ? [first, last] : [];
}
export function weekPage(snapshot: Snapshot, state: AppState, day: number): WeekPage {
  const first = monday(day), all = meetings(snapshot, first), events = state.events.filter((e: AgendaEvent) => dayNumber(e.date) >= first && dayNumber(e.date) < first + 7);
  const page: WeekPage = { day: first, key: dateText(first), meetings: all, events: events, blocks: [], outside: [] };
  for (let date = first; date < first + 7; date++) {
    const daily = all.filter((m: Meeting) => m.day === date && span(m.rule).length).sort((a: Meeting, b: Meeting) => span(a.rule)[0] - span(b.rule)[0]);
    for (let i = 0; i < daily.length;) {
      let next = i + 1, last = span(daily[i].rule)[1]; while (next < daily.length && span(daily[next].rule)[0] <= last) { last = Math.max(last, span(daily[next].rule)[1]); next++; }
      const group = daily.slice(i, next), warnings = events.filter((e: AgendaEvent) => e.date === dateText(date) && !e.done && !e.allDay && group.some((m: Meeting) => overlaps(e.start, e.end, m.rule.start, m.rule.end))).length;
      page.blocks.push({ id: group[0].key, day: date, first: span(group[0].rule)[0] - 1, last: last, meetings: group, conflicts: warnings + group.length - 1 }); i = next;
    }
  }
  all.filter((m: Meeting) => !span(m.rule).length).forEach((m: Meeting) => page.outside.push({ id: m.key, title: m.rule.course, place: m.rule.room, time: m.rule.start + '—' + m.rule.end, order: m.rule.start, done: false, meeting: m }));
  for (const e of events) {
    const range = agendaSpan(e), date = dayNumber(e.date);
    const collision = all.some((m: Meeting) => m.day === date && overlaps(e.start, e.end, m.rule.start, m.rule.end)) || events.some((other: AgendaEvent) => other.id !== e.id && !other.done && !other.allDay && other.date === e.date && overlaps(e.start, e.end, other.start, other.end));
    if (range.length && !collision) page.blocks.push({ id: e.id, day: date, first: range[0], last: range[1], meetings: [], event: e, conflicts: 0 });
    else page.outside.push({ id: e.id, title: e.title, place: e.place + (collision && !e.allDay && !e.done ? ' · 时间冲突' : ''), time: e.date.slice(5) + ' ' + (e.allDay ? '全天' : e.start + '—' + e.end), order: e.date + e.start, done: e.done, event: e });
  }
  return page;
}
export function conflictsToday(snapshot: Snapshot, state: AppState, day: number, now: number): string[] {
  const items = agenda(snapshot, state, day, now).filter((i: TimelineItem) => !i.done && !i.event?.allDay), result: string[] = [];
  for (let i = 0; i < items.length; i++) for (let j = i + 1; j < items.length && result.length < 50; j++) {
    const a = items[i], b = items[j], start = a.meeting?.rule.start || a.event?.start || '', end = a.meeting?.rule.end || a.event?.end || '';
    if (overlaps(start, end, b.meeting?.rule.start || b.event?.start || '', b.meeting?.rule.end || b.event?.end || '')) result.push(a.title + ' ↔ ' + b.title);
  }
  return result;
}
export function editConflicts(snapshot: Snapshot, state: AppState, ids: string[], edits: Rule[]): string[] {
  const result: Set<string> = new Set<string>(), mondayStart = monday(dayNumber(snapshot.startDate));
  for (const rule of edits) {
    for (const other of snapshot.rules) if (!ids.includes(other.id || '') && rule.day === other.day && rule.from <= other.to && other.from <= rule.to && overlaps(rule.start, rule.end, other.start, other.end)) { result.add('课程：' + other.course + ' · 周' + '一二三四五六日'.charAt(other.day - 1) + ' ' + other.start + '—' + other.end); if (result.size >= 20) return Array.from(result); }
    for (const e of state.events) { const date = dayNumber(e.date), w = week(date, snapshot.startDate); if (!e.done && !e.allDay && weekday(date) === rule.day && w >= rule.from && w <= rule.to && overlaps(rule.start, rule.end, e.start, e.end)) result.add('日程：' + e.title + ' · ' + e.date); }
  }
  for (let i = 0; i < edits.length; i++) for (let j = i + 1; j < edits.length && result.size < 20; j++) { const a = edits[i], b = edits[j]; if (a.day === b.day && a.from <= b.to && b.from <= a.to && overlaps(a.start, a.end, b.start, b.end)) result.add('新增时段之间存在重叠'); }
  return Array.from(result).slice(0, 20);
}
export function eventConflicts(snapshot: Snapshot, state: AppState, event: AgendaEvent): string[] {
  if (event.done || event.allDay) return [];
  const date = dayNumber(event.date), result: string[] = [];
  for (const r of courses(snapshot, date)) if (overlaps(event.start, event.end, r.start, r.end)) result.push(r.course + ' · ' + r.start + '—' + r.end);
  for (const e of state.events) if (e.id !== event.id && e.date === event.date && !e.done && !e.allDay && overlaps(event.start, event.end, e.start, e.end)) result.push(e.title + ' · ' + e.start + '—' + e.end);
  return result.slice(0, 20);
}
export function ruleTint(rule: Rule, fallback: string, dark: boolean = false): string {
  if (!rule.color) return fallback;
  let color = rule.color >>> 0;
  if (dark) { const r = Math.round(((color >> 16) & 255) * 0.42 + 18 * 0.58), g = Math.round(((color >> 8) & 255) * 0.42 + 27 * 0.58), b = Math.round((color & 255) * 0.42 + 36 * 0.58); color = (r << 16) | (g << 8) | b; }
  return '#' + color.toString(16).padStart(8, '0').slice(-6);
}
interface ChangeGroup { course: string; day: number; start: string; end: string; rules: Rule[]; }
function changeGroups(snapshot: Snapshot): Map<string, ChangeGroup> {
  const groups: Map<string, ChangeGroup> = new Map<string, ChangeGroup>();
  for (const r of snapshot.rules) { const key = JSON.stringify([r.course, r.day, r.start, r.end]); let g = groups.get(key); if (!g) { g = { course: r.course, day: r.day, start: r.start, end: r.end, rules: [] }; groups.set(key, g); } g.rules.push(r); }
  return groups;
}
function weekRules(group: ChangeGroup | undefined, week: number): Rule[] { return group ? group.rules.filter((r: Rule) => r.from <= week && r.to >= week) : []; }
function signature(rules: Rule[]): string { return JSON.stringify(rules.map((r: Rule) => JSON.stringify([r.room, r.teacher, r.type, r.credits || '', r.note || '', r.color || 0])).sort()); }
function places(rules: Rule[]): string { return rules.map((r: Rule) => r.room + (r.teacher ? ' / ' + r.teacher : '')).join('、'); }
export function syncChanges(before: Snapshot, after: Snapshot): ChangeLine[] {
  if (!before.rules.length) return [];
  const old = changeGroups(before), next = changeGroups(after), keys: Set<string> = new Set<string>(), result: ChangeLine[] = [];
  old.forEach((_g: ChangeGroup, key: string) => keys.add(key)); next.forEach((_g: ChangeGroup, key: string) => keys.add(key));
  if (before.startDate !== after.startDate) result.push({ kind: '变更', text: '开学日期：' + before.startDate + ' → ' + after.startDate });
  // Compare per group/week without constructing 265,000 expanded occurrence strings.
  for (const key of keys) {
    const group = old.get(key) || next.get(key); if (!group) continue;
    for (let w = 1; w <= 53 && result.length < 200; w++) {
      const previous = weekRules(old.get(key), w), current = weekRules(next.get(key), w);
      if (signature(previous) === signature(current)) continue;
      const label = group.course + ' · 第' + w + '周 周' + '一二三四五六日'.charAt(group.day - 1) + ' ' + group.start + '—' + group.end;
      result.push({ kind: !previous.length ? '新增' : !current.length ? '取消' : '变更', text: label + ' · ' + (!previous.length ? places(current) : !current.length ? places(previous) : places(previous) + ' → ' + places(current)) });
    }
    if (result.length >= 200) break;
  }
  return result;
}
