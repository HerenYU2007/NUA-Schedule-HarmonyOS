import { common } from '@kit.AbilityKit';
import { Snapshot, Rule, nowDay } from '../model/Schedule';
import { AppState, defaultState, meetings, ReminderOverride } from '../model/AppModel';
import { CourseParams } from '../model/Navigation';
import { CourseDraft, draftFor, newDraft, slotRules, draftsToRules, mergeSlots, editConflicts } from '../model/Parity';
import { load } from '../services/Store';
import { loadApp } from '../services/AppStore';
import { restoreBundle } from '../services/AtomicStore';
import { refreshAllForms } from '../services/Forms';
import { scheduleReminders } from '../services/Reminders';
@Entry
@Component
struct CourseEdit {
  @State name: string = '';
  @State color: number = 0;
  @State credits: string = '';
  @State note: string = '';
  @State slots: CourseDraft[] = [];
  @State error: string = '';
  @State dark: boolean = false;
  private snapshot: Snapshot = { schema: 1, startDate: '2026-09-07', rules: [], syncedAt: 0 };
  private app: AppState = defaultState();
  private originals: Rule[] = [];
  private loaded: boolean = false;
  private saved: boolean = false;
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private bg(): string { return this.dark ? '#121B24' : '#F7F9FB'; }
  private surface(): string { return this.dark ? '#23313F' : '#FFFFFF'; }
  private ink(): string { return this.dark ? '#E8EFF5' : '#243746'; }
  aboutToAppear(): void {
    try {
      this.snapshot = load(this.context()); this.app = loadApp(this.context());
      this.dark = this.app.preferences.theme === 2 || (this.app.preferences.theme === 0 && (AppStorage.get<boolean>('systemDark') || false));
      const params = this.getUIContext().getRouter().getParams() as CourseParams;
      const day = params?.day ?? nowDay(), selected = meetings(this.snapshot, day, 1).find((m) => m.rule.id === params?.ruleId);
      if (params?.ruleId && !selected) throw new Error('该课程已变化，请返回后重新打开');
      if (selected) { this.originals = slotRules(this.snapshot, selected); this.name = selected.rule.course; this.color = selected.rule.color ?? 0; this.credits = selected.rule.credits ?? ''; this.note = selected.rule.note ?? ''; this.slots = [draftFor(this.snapshot, selected)]; }
      else this.slots = [newDraft(this.snapshot, day, params?.first ?? 1, params?.last ?? 2)];
      this.loaded = true;
    } catch (e) { this.error = (e as Error).message; }
  }
  private changed(): void { this.slots = this.slots.slice(); }
  private time(index: number, end: boolean): void {
    const text = end ? this.slots[index].end : this.slots[index].start;
    this.getUIContext().showTimePickerDialog({ selected: new Date(2026, 0, 1, Number(text.slice(0, 2)), Number(text.slice(3))), useMilitaryTime: true, onAccept: (value: TimePickerResult) => {
      const next = String(value.hour).padStart(2, '0') + ':' + String(value.minute).padStart(2, '0');
      if (end) this.slots[index].end = next; else this.slots[index].start = next; this.changed();
    } });
  }
  private persist(edits: Rule[]): void {
    try {
      if (!this.loaded || this.saved) return;
      const latest = load(this.context());
      if (JSON.stringify(latest) !== JSON.stringify(this.snapshot)) throw new Error('课表已变化，请返回重新编辑');
      const next = mergeSlots(latest, this.originals.map((r: Rule) => r.id || ''), edits), app = loadApp(this.context());
      const oldName = this.originals[0]?.course;
      if (oldName && oldName !== this.name && edits.length) {
        const prior = (app.overrides || []).find((o: ReminderOverride) => o.key === 'course:' + oldName);
        if (prior && !(app.overrides || []).some((o: ReminderOverride) => o.key === 'course:' + this.name)) app.overrides?.push({ key: 'course:' + this.name, mode: prior.mode, minutes: prior.minutes });
        if (app.preferences.selectedCourses?.includes(oldName) && !app.preferences.selectedCourses.includes(this.name)) app.preferences.selectedCourses.push(this.name);
      }
      restoreBundle(this.context(), JSON.stringify(next), JSON.stringify(app)); this.saved = true;
      refreshAllForms(this.context()).catch(() => {}); scheduleReminders(this.context()).catch(() => {});
      this.getUIContext().getRouter().back();
    } catch (e) { this.error = (e as Error).message || '保存失败，原课表已保留'; }
  }
  private save(): void {
    try {
      if (!this.loaded) return;
      this.name = this.name.trim();
      const edits = draftsToRules(this.slots, this.name, this.color, this.credits, this.note, this.originals, 'manual-' + Date.now());
      mergeSlots(this.snapshot, this.originals.map((r: Rule) => r.id || ''), edits);
      const warning = editConflicts(this.snapshot, this.app, this.originals.map((r: Rule) => r.id || ''), edits);
      if (warning.length) this.getUIContext().showAlertDialog({ title: '这些安排时间重叠', message: warning.join('\n') + '\n仍要保存吗？', primaryButton: { value: '返回修改', action: () => {} }, secondaryButton: { value: '仍然保存', action: () => this.persist(edits) } });
      else this.persist(edits);
    } catch (e) { this.error = (e as Error).message; }
  }
  @Builder private caption(text: string) { Text(text).fontColor(this.ink()).fontSize(14).width('100%').margin({ top: 12, bottom: 6 }) }
  build() {
    Column() {
      Row() {
        Button('取消').backgroundColor(this.surface()).fontColor(this.ink()).onClick(() => this.getUIContext().getRouter().back())
        Text(this.originals.length ? '修改课程' : '新增课程').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.ink()).layoutWeight(1).textAlign(TextAlign.Center)
        Button('保存').backgroundColor('#1F4E78').fontColor('#FFFFFF').enabled(this.loaded).onClick(() => this.save())
      }.padding(16).width('100%')
      Scroll() {
        Column({ space: 12 }) {
          Column() {
            this.caption('课程名称')
            TextInput({ text: this.name, placeholder: '填写课程名称' }).maxLength(120).fontColor(this.ink()).backgroundColor(this.bg()).onChange((v: string) => { this.name = v; })
            this.caption('颜色 · 自动 / 自选')
            Row({ space: 10 }) { ForEach([0, 0x8BCAE8, 0xF2B7C7, 0x99D6D1, 0xC4B4F0, 0xEAC28B, 0xECA891], (c: number) => {
              Text(c === this.color ? '✓' : '').fontColor('#243746').width(30).height(30).textAlign(TextAlign.Center).borderRadius(15).backgroundColor(c ? '#' + c.toString(16).padStart(6, '0') : '#DDE5EB').onClick(() => { this.color = c; })
            }) }.width('100%')
            this.caption('学分（选填）')
            TextInput({ text: this.credits, placeholder: '例如 2' }).maxLength(40).fontColor(this.ink()).backgroundColor(this.bg()).onChange((v: string) => { this.credits = v; })
          }.padding(18).width('100%').backgroundColor(this.surface()).borderRadius(22)
          ForEach(this.slots, (slot: CourseDraft, index: number) => {
            Column({ space: 12 }) {
              Row() {
                Text('时段 ' + (index + 1)).fontWeight(FontWeight.Bold).fontSize(18).fontColor(this.ink()).layoutWeight(1)
                Button('复制').fontSize(12).backgroundColor(this.bg()).fontColor(this.ink()).onClick(() => { this.slots = this.slots.concat([JSON.parse(JSON.stringify(slot)) as CourseDraft]); })
                Button('删除').fontSize(12).backgroundColor(this.bg()).fontColor('#BC3045').enabled(this.slots.length > 1).onClick(() => { this.slots = this.slots.filter((_s: CourseDraft, i: number) => i !== index); })
              }
              TextInput({ text: slot.weeks, placeholder: '周数：1-16 或 1-16单' }).maxLength(200).fontColor(this.ink()).backgroundColor(this.bg()).onChange((v: string) => { slot.weeks = v; })
              Row({ space: 6 }) {
                Select(['周一', '周二', '周三', '周四', '周五', '周六', '周日'].map((s: string): SelectOption => ({ value: s }))).layoutWeight(1).selected(slot.day - 1).value('周' + '一二三四五六日'.charAt(slot.day - 1)).onSelect((i: number) => { slot.day = i + 1; this.changed(); })
                Select(Array.from({ length: 12 }, (_v: number, i: number): SelectOption => ({ value: '第' + (i + 1) + '节' }))).layoutWeight(1).selected(slot.first - 1).value('第' + slot.first + '节').onSelect((i: number) => { slot.first = i + 1; if (slot.last < slot.first) slot.last = slot.first; this.changed(); })
                Select(Array.from({ length: 12 }, (_v: number, i: number): SelectOption => ({ value: '至' + (i + 1) + '节' }))).layoutWeight(1).selected(slot.last - 1).value('至' + slot.last + '节').onSelect((i: number) => { slot.last = i + 1; this.changed(); })
              }.width('100%')
              Row() { Text('自定义时间').fontColor(this.ink()).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: slot.custom }).onChange((v: boolean) => { slot.custom = v; this.changed(); }); }
              if (slot.custom) { Row({ space: 12 }) { Button(slot.start).onClick(() => this.time(index, false)); Button(slot.end).onClick(() => this.time(index, true)); } }
              TextInput({ text: slot.room, placeholder: '教室 / 地点' }).maxLength(300).fontColor(this.ink()).backgroundColor(this.bg()).onChange((v: string) => { slot.room = v; })
              TextInput({ text: slot.teacher, placeholder: '教师（选填）' }).maxLength(400).fontColor(this.ink()).backgroundColor(this.bg()).onChange((v: string) => { slot.teacher = v; })
            }.padding(18).backgroundColor(this.surface()).borderRadius(22).width('100%')
          })
          TextArea({ text: this.note, placeholder: '备注（选填）' }).maxLength(2000).height(120).fontColor(this.ink()).backgroundColor(this.surface()).onChange((v: string) => { this.note = v; })
          Text('仅编辑所点课程的这个时段；其他时间、教室的同名课不会一起改动。').fontSize(12).fontColor(this.ink()).opacity(0.7)
          if (this.error) { Text(this.error).fontColor('#BC3045').fontSize(14); }
          if (this.originals.length) { Button('删除当前时段').width('100%').backgroundColor(this.surface()).fontColor('#BC3045').onClick(() => this.getUIContext().showAlertDialog({ title: '删除这个上课时段？', message: '只删除当前编辑时段涵盖的周次，其他时段不变。', primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '删除', action: () => this.persist([]) } })); }
        }.padding(16).width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(this.bg())
  }
}
