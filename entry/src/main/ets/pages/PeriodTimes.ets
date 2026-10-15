import { common } from '@kit.AbilityKit';
import { PeriodClock, defaultClock, validClock } from '../model/SchoolClock';
import { loadClock, saveClock } from '../services/ClockStore';
import { loadApp } from '../services/AppStore';
import { refreshAllForms } from '../services/Forms';
import { scheduleReminders } from '../services/Reminders';
@Entry
@Component
struct PeriodTimes {
  @State draft: PeriodClock = defaultClock();
  @State dark: boolean = false;
  @State error: string = '';
  @State ready: boolean = false;
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  aboutToAppear(): void {
    try { this.draft = loadClock(this.context()); const theme = loadApp(this.context()).preferences.theme; this.dark = theme === 2 || (theme === 0 && (AppStorage.get<boolean>('systemDark') || false)); this.ready = true; }
    catch (_) { this.error = '时间设置读取失败，禁止覆盖，请返回重试'; }
  }
  private pick(period: number, end: boolean): void {
    const value = end ? this.draft.ends[period] : this.draft.starts[period];
    this.getUIContext().showTimePickerDialog({ selected: new Date(2026, 0, 1, Number(value.slice(0, 2)), Number(value.slice(3))), useMilitaryTime: true,
      onAccept: (result: TimePickerResult) => {
        const text = String(result.hour).padStart(2, '0') + ':' + String(result.minute).padStart(2, '0');
        const next: PeriodClock = { starts: this.draft.starts.slice(), ends: this.draft.ends.slice() };
        if (end) next.ends[period] = text; else next.starts[period] = text;
        this.draft = next; this.error = '';
      } });
  }
  private save(): void {
    if (!this.ready) return;
    try { validClock(this.draft); } catch (e) { this.error = (e as Error).message; return; }
    this.getUIContext().showAlertDialog({ title: '保存全局节次时间？', message: '按节次安排的课程、提醒和桌面卡片将使用新时间。单独设置了自定义时间的课程和个人日程不变。', primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '保存', action: () => {
      try { saveClock(this.context(), this.draft); } catch (_) { this.error = '保存失败，原时间保留'; return; }
      refreshAllForms(this.context()).catch(() => {}); scheduleReminders(this.context()).catch(() => {});
      this.getUIContext().getPromptAction().showToast({ message: '节次时间已保存' }); this.getUIContext().getRouter().back();
    } } });
  }
  build() {
    Column({ space: 14 }) {
      Row() {
        Button('返回').fontColor(this.dark ? '#9ED6FF' : '#1F4E78').backgroundColor(Color.Transparent).onClick(() => this.getUIContext().getRouter().back())
        Text('全局节次时间').fontSize(21).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Button('保存').enabled(this.ready).onClick(() => this.save())
      }.width('100%')
      Text('点开始或结束时间进行调整；各节时间不能重叠。修改草稿后点击保存才生效。').fontSize(14).fontColor(this.dark ? '#BAC8D4' : '#5B6B78')
      if (this.error) { Text(this.error).fontColor(this.dark ? '#FFA3AB' : '#BC3045').fontSize(14) }
      Scroll() {
        Column({ space: 10 }) {
          ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], (period: number) => {
            Row({ space: 10 }) {
              Text('第' + period + '节').layoutWeight(1).fontSize(17)
              Button(this.draft.starts[period]).fontSize(17).fontColor(this.dark ? '#9ED6FF' : '#1F4E78').backgroundColor(this.dark ? '#23313F' : '#EDF2F5').onClick(() => this.pick(period, false))
              Text('—')
              Button(this.draft.ends[period]).fontSize(17).fontColor(this.dark ? '#9ED6FF' : '#1F4E78').backgroundColor(this.dark ? '#23313F' : '#EDF2F5').onClick(() => this.pick(period, true))
            }.width('100%').padding(14).backgroundColor(this.dark ? '#1C2833' : '#FFFFFF').borderRadius(18)
          }, (period: number) => String(period))
          Button('恢复默认时间').enabled(this.ready).onClick(() => this.getUIContext().showAlertDialog({ title: '恢复默认时间？', message: '仅重置草稿，点击保存后生效。', primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '恢复', action: () => { this.draft = defaultClock(); this.error = ''; } } }))
        }.width('100%')
      }.layoutWeight(1).width('100%')
    }.padding(16).width('100%').height('100%').backgroundColor(this.dark ? '#121B24' : '#F7F9FB').foregroundColor(this.dark ? '#E8EFF5' : '#243746')
  }
}
