import { common } from '@kit.AbilityKit';
import { PeriodClock, defaultClock, validClock, useClock, upgradePreviousDefault } from '../model/SchoolClock';
import { readJson, writeJson } from './AtomicStore';
export function loadClock(context: common.Context): PeriodClock {
  const value = upgradePreviousDefault(JSON.parse(readJson(context, 'period-clock.json', JSON.stringify(defaultClock()))) as PeriodClock);
  useClock(value); return value;
}
export function saveClock(context: common.Context, value: PeriodClock): void {
  validClock(value);
  const saved: PeriodClock = { starts: value.starts.slice(), ends: value.ends.slice(), revision: 2 };
  writeJson(context, 'period-clock.json', JSON.stringify(saved)); useClock(saved);
  try { AppStorage.setOrCreate('scheduleRevision', (AppStorage.get<number>('scheduleRevision') || 0) + 1); } catch (_) {}
}
