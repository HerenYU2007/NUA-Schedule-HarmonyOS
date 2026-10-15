import { util } from '@kit.ArkTS';
import { Backup, parseBackup, calendarText, spreadsheetBytes } from '../model/ExportLogic';
@Concurrent
export function generateExport(text: string, kind: string): ArrayBuffer {
  const restored = parseBackup(text);
  if (kind === 'xls') return spreadsheetBytes(restored.snapshot).buffer as ArrayBuffer;
  const value = kind === 'ics' ? calendarText(restored.snapshot) : text;
  return new util.TextEncoder().encodeInto(value).buffer as ArrayBuffer;
}
