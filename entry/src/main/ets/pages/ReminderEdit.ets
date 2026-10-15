import { common } from '@kit.AbilityKit';
import { AppState, Meeting, defaultState, meetings, reminderKey, ReminderOverride } from '../model/AppModel';
import { ReminderParams } from '../model/Navigation';
import { nowDay, dateText } from '../model/Schedule';
import { load } from '../services/Store';
import { loadApp, saveApp } from '../services/AppStore';
import { allowNotifications, scheduleReminders } from '../services/Reminders';
@Entry
@Component
struct ReminderEdit {
  @State app: AppState = defaultState();
  @State lesson: Meeting | undefined = undefined;
  @State single: boolean = true;
  @State modes: number[] = [-1, -1];
  @State advances: string[] = ['15', '15'];
  @State error: string = '';
  @State dark: boolean = false;
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private ink(): string { return this.dark ? '#E8EFF5' : '#243746'; }
  private surface(): string { return this.dark ? '#23313F' : '#FFFFFF'; }
  private index(): number { return this.single ? 0 : 1; }
  aboutToAppear(): void {
    try {
      const p = this.getUIContext().getRouter().getParams() as ReminderParams;
      this.app = loadApp(this.context()); this.lesson = meetings(load(this.context()), p.day ?? nowDay(), 1).find((m: Meeting) => m.rule.id === p.ruleId);
      if (!this.lesson) throw new Error('课程已变化，请返回重新打开');
      this.dark = this.app.preferences.theme === 2 || (this.app.preferences.theme === 0 && (AppStorage.get<boolean>('systemDark') || false));
      [true, false].forEach((single: boolean, i: number) => { const item = (this.app.overrides || []).find((o: ReminderOverride) => o.key === reminderKey(this.lesson!, single)); this.modes[i] = item?.mode ?? -1; this.advances[i] = String(item?.minutes ?? this.app.preferences.minutes); });
    } catch (e) { this.error = (e as Error).message; }
  }
  private save(): void {
    try {
      if (!this.lesson) return;
      const minutes = Number(this.advances[this.index()]); if (!/^\d{1,3}$/.test(this.advances[this.index()]) || minutes > 120) throw new Error('请填写0—120分钟');
      const state = loadApp(this.context()), key = reminderKey(this.lesson, this.single), mode = this.modes[this.index()];
      state.overrides = (state.overrides || []).filter((o: ReminderOverride) => o.key !== key);
      if (mode >= 0) state.overrides.push({ key: key, mode: mode, minutes: minutes });
      saveApp(this.context(), state);
      if (mode > 0 && state.preferences.reminders) allowNotifications(this.context()).then(() => scheduleReminders(this.context())).catch(() => {});
      else scheduleReminders(this.context()).catch(() => {});
      this.getUIContext().getRouter().back();
    } catch (e) { this.error = (e as Error).message; }
  }
  build() {
    Column({ space: 18 }) {
      Row() { Button('返回').fontColor(this.ink()).backgroundColor(this.surface()).onClick(() => this.getUIContext().getRouter().back()); Blank(); Text('单独提醒').fontSize(23).fontColor(this.ink()).fontWeight(FontWeight.Bold); Blank(); Button('保存').onClick(() => this.save()); }.width('100%')
      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 12 }) { Text(this.lesson?.rule.course || '课程提醒').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.ink()); Text(this.lesson ? dateText(this.lesson.day) + ' · ' + this.lesson.rule.start + '—' + this.lesson.rule.end + '\n' + this.lesson.rule.room : '').fontSize(15).fontColor(this.ink()); }.padding(24).width('100%').backgroundColor(this.surface()).borderRadius(24)
          Column({ space: 18 }) {
            Text('应用范围').fontSize(16).fontColor(this.ink()).width('100%')
            Row({ space: 12 }) { Button('仅这一次').fontSize(13).layoutWeight(1).backgroundColor(this.single ? '#1F4E78' : '#687A89').onClick(() => { this.single = true; }); Button('这门课的所有时段').fontSize(13).layoutWeight(1).backgroundColor(this.single ? '#687A89' : '#1F4E78').onClick(() => { this.single = false; }); }
            Select(['跟随总设置', '不提醒', '通知提醒', '闹钟提醒'].map((v: string): SelectOption => ({ value: v }))).selected(this.modes[this.index()] + 1).value(['跟随总设置', '不提醒', '通知提醒', '闹钟提醒'][this.modes[this.index()] + 1]).onSelect((i: number) => { this.modes[this.index()] = i - 1; this.modes = this.modes.slice(); })
            TextInput({ text: this.advances[this.index()], placeholder: '提前分钟数（0—120）' }).type(InputType.Number).maxLength(3).fontColor(this.ink()).onChange((v: string) => { this.advances[this.index()] = v; })
          }.padding(24).width('100%').backgroundColor(this.surface()).borderRadius(24)
          Text(this.app.preferences.reminders ? '单次设置优先于整门课设置；闹钟通过系统提醒代理响铃，可从通知关闭。' : '总设置的上课提醒尚未开启。此处设置会保留，开启总开关后才生效。').fontSize(14).fontColor(this.ink()).lineHeight(23)
          if (this.error) { Text(this.error).fontColor('#BC3045'); }
        }.width('100%')
      }.layoutWeight(1).width('100%')
    }.padding(20).width('100%').height('100%').backgroundColor(this.dark ? '#121B24' : '#F7F9FB')
  }
}
