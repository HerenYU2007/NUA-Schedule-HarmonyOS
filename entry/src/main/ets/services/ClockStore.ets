import { common } from '@kit.AbilityKit';
import { PeriodClock, defaultClock, validClock, useClock } from '../model/SchoolClock';
import { readJson, writeJson } from './AtomicStore';
export function loadClock(context: common.Context): PeriodClock {
  const value = validClock(JSON.parse(readJson(context, 'period-clock.json', JSON.stringify(defaultClock()))) as PeriodClock);
  useClock(value); return value;
}
export function saveClock(context: common.Context, value: PeriodClock): void {
  validClock(value); writeJson(context, 'period-clock.json', JSON.stringify(value)); useClock(value);
  try { AppStorage.setOrCreate('scheduleRevision', (AppStorage.get<number>('scheduleRevision') || 0) + 1); } catch (_) {}
}
