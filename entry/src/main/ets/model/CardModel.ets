import { Snapshot, CardLine, cardData, dateText, nowDay, week } from './Schedule';
import { monday, defaultState, countdown } from './AppModel';
import { weekPage, BoardBlock } from './Parity';
import { dailyCardCapacity } from './CardLayout';
export interface WeekCardBlock { id: string; day: number; first: number; last: number; label: string; }
export interface CardPayload { title: string; subtitle: string; lines: CardLine[]; empty: string; overflow: string; next: string; availableHeight: number; white: boolean; kind: string; weekDay: number; weekBlocks: WeekCardBlock[]; dates: string[]; }
export function cardPayload(snapshot: Snapshot, kind: string, white: boolean, offset: number, weekOffset: number, capacity: number, height: number, now: number = Date.now()): CardPayload {
  const daily = cardData(snapshot, offset, now, Math.min(dailyCardCapacity(height), Math.max(2, capacity))), first = monday(nowDay(now)) + weekOffset * 7;
  const result: CardPayload = { title: daily.title, subtitle: daily.subtitle, lines: daily.lines, empty: daily.empty, overflow: daily.overflow, next: countdown(snapshot, now), availableHeight: height, white: white, kind: kind, weekDay: first, weekBlocks: [], dates: [] };
  if (kind === 'week') {
    result.title = '第' + week(first, snapshot.startDate) + '周 · ' + dateText(first).slice(5).replace('-', '/'); result.subtitle = '点击课表打开应用';
    result.dates = [0, 1, 2, 3, 4, 5, 6].map((i: number) => '一二三四五六日'.charAt(i) + '\n' + Number(dateText(first + i).slice(8)));
    result.weekBlocks = weekPage(snapshot, defaultState(), first).blocks.map((b: BoardBlock): WeekCardBlock => ({ id: b.id, day: b.day - first, first: b.first, last: b.last, label: b.meetings[0].rule.course + '\n@' + b.meetings[0].rule.room + (b.meetings.length > 1 ? '\n+' + (b.meetings.length - 1) : '') }));
    result.empty = snapshot.rules.length ? '本周没有课程' : '尚未导入课表';
  }
  return result;
}
