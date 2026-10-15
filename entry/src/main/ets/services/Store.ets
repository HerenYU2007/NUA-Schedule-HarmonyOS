import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Snapshot, validSnapshot } from '../model/Schedule';
import { readJson, writeJson } from './AtomicStore';
import { loadClock } from './ClockStore';
function prefs(context: common.Context): preferences.Preferences {
  preferences.removePreferencesFromCacheSync(context, 'nua_schedule');
  return preferences.getPreferencesSync(context, { name: 'nua_schedule' });
}
export function load(context: common.Context): Snapshot {
  loadClock(context);
  return validSnapshot(JSON.parse(readJson(context, 'schedule.json', '{"schema":1,"startDate":"2026-09-07","rules":[],"syncedAt":0}')) as Snapshot);
}
export function save(context: common.Context, value: Snapshot): void {
  writeJson(context, 'schedule.json', JSON.stringify(validSnapshot(value)));
  // UI-process subscribers refresh without waiting for a tab switch. Not a cross-process bus.
  try { AppStorage.setOrCreate('scheduleRevision', (AppStorage.get<number>('scheduleRevision') || 0) + 1); } catch (_) {}
}
export interface FormChoice { id: string; date: string; offset: number; capacity: number; height?: number; kind?: string; white?: boolean; weekOffset?: number; }
export function formChoices(context: common.Context): FormChoice[] { return JSON.parse(prefs(context).getSync('forms', '[]') as string) as FormChoice[]; }
export function saveChoices(context: common.Context, choices: FormChoice[]): void { const data = prefs(context); data.putSync('forms', JSON.stringify(choices)); data.flushSync(); }
