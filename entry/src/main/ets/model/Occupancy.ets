import { WeekPage, overlaps } from './Parity';
import { Meeting, AgendaEvent } from './AppModel';
import { PERIOD_START, PERIOD_END } from './SchoolClock';
import { dateText } from './Schedule';
// Cached page data is enough for hit testing; never clone the full semester into every Swiper child.
export function pageFree(data: WeekPage, day: number, first: number, last: number): boolean {
  if (first < 1 || last > 12 || first > last) return false;
  return !data.meetings.some((m: Meeting) => m.day === day && overlaps(PERIOD_START[first], PERIOD_END[last], m.rule.start, m.rule.end)) && !data.events.some((e: AgendaEvent) => !e.done && !e.allDay && e.date === dateText(day) && overlaps(PERIOD_START[first], PERIOD_END[last], e.start, e.end));
}
