import { Snapshot } from './Schedule';
import { AppState, monday } from './AppModel';
import { WeekPage, weekPage } from './Parity';
export class WeekData implements IDataSource {
  private static nextRevision: number = 0;
  private revision: number = 0;
  private listeners: DataChangeListener[] = [];
  private cache: Map<number, WeekPage> = new Map<number, WeekPage>();
  private snapshot: Snapshot;
  private state: AppState;
  private anchor: number;
  constructor(snapshot: Snapshot, state: AppState, anchor: number) { this.snapshot = snapshot; this.state = state; this.anchor = monday(anchor); this.revision = ++WeekData.nextRevision; }
  totalCount(): number { return 107; }
  dayAt(index: number): number { return this.anchor + (index - 53) * 7; }
  getData(index: number): WeekPage {
    let value = this.cache.get(index); if (!value) { value = weekPage(this.snapshot, this.state, this.dayAt(index)); value.key += '@' + this.revision; this.cache.set(index, value); }
    if (this.cache.size > 7) { let farthest = -1, distance = -1; this.cache.forEach((_page: WeekPage, key: number) => { if (Math.abs(key - index) > distance) { farthest = key; distance = Math.abs(key - index); } }); this.cache.delete(farthest); }
    return value;
  }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter((v: DataChangeListener) => v !== listener); }
}
