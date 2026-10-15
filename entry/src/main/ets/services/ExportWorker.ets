import { util } from '@kit.ArkTS';
import { Backup, parseBackup, calendarText, spreadsheetBytes } from '../model/ExportLogic';
import { PeriodClock, useClock } from '../model/SchoolClock';
@Concurrent
export function generateExport(text: string, kind: string, clock: string): ArrayBuffer {
  // Taskpool modules have their own globals: initialize before normalizing a backup.
  useClock(JSON.parse(clock) as PeriodClock);
  const restored = parseBackup(text);
  if (kind === 'xls') return spreadsheetBytes(restored.snapshot).buffer as ArrayBuffer;
  const value = kind === 'ics' ? calendarText(restored.snapshot) : text;
  return new util.TextEncoder().encodeInto(value).buffer as ArrayBuffer;
}
