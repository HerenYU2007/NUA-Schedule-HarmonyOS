import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Snapshot, dateText, dayNumber, nowDay, weekday, week, courseStatus } from '../model/Schedule';
import { AppState, AgendaEvent, TimelineItem, Meeting, GridBlock, defaultState, validEvent, meetings, monday, agenda, countdown, span, gridBlocks, courseColor, PERIOD_START, PERIOD_END } from '../model/AppModel';
import { load, save } from '../services/Store';
import { loadApp, saveApp, readJson } from '../services/AppStore';
import { pendingChanges, acknowledgeChanges } from '../services/Changes';
import { refreshAllForms } from '../services/Forms';
import { allowNotifications, scheduleReminders } from '../services/Reminders';
import { checkUpdate, openUpdate, UpdateResult } from '../services/Updates';
import { WeekData } from '../model/WeekData';
import { WeekPage, conflictsToday, eventConflicts } from '../model/Parity';
import { WeekBoard } from '../ui/WeekBoard';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Entry
@Component
struct Index {
  @State snapshot: Snapshot = { schema: 1, startDate: '2026-09-07', rules: [], syncedAt: 0 };
  @State app: AppState = defaultState();
  @State day: number = nowDay();
  @State page: number = 1;
  @State clock: number = Date.now();
  @State error: string = '';
  @State expanded: boolean = true;
  @State weeks: WeekData = new WeekData(this.snapshot, this.app, nowDay());
  @State weekIndex: number = 53;
  @State dragActive: boolean = false;
  @State cancelRevision: number = 0;
  @State detail: Meeting | undefined = undefined;
  @State editing: boolean = false;
  @State draft: AgendaEvent = { id: '', title: '', place: '', date: dateText(nowDay()), start: '09:00', end: '10:00', allDay: false, done: false, remind: false };
  @State formError: string = '';
  @State reminderStatus: string = '';
  @State updating: boolean = false;
  @StorageLink('systemDark') systemDark: boolean = false;
  @StorageLink('cardWeek') @Watch('fromCard') cardWeek: number = 0;
  @StorageLink('scheduleRevision') @Watch('scheduleChanged') scheduleRevision: number = 0;
  private timer: number = -1;
  private loaded: boolean = false;
  private promptHandled: boolean = false;
  private promptOpen: boolean = false;
  private visible: boolean = false;
  private autoChecked: boolean = false;
  private manualWaiting: boolean = false;
  private deferredUpdate: UpdateResult | undefined = undefined;
  private scroller: Scroller = new Scroller();
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private dark(): boolean { return this.app.preferences.theme === 2 || (this.app.preferences.theme === 0 && this.systemDark); }
  private bg(): string { return this.dark() ? '#121B24' : '#F7F9FB'; }
  private surface(): string { return this.dark() ? '#1C2833' : '#FFFFFF'; }
  private primary(): string { return this.dark() ? '#E8EFF5' : '#243746'; }
  private secondary(): string { return this.dark() ? '#BAC8D4' : '#5B6B78'; }
  private brand(): string { return this.dark() ? '#9ED6FF' : '#1F4E78'; }
  private control(): string { return this.dark() ? '#23313F' : '#EDF2F5'; }
  private onBrand(): string { return this.dark() ? '#102A3E' : '#FFFFFF'; }
  private fromCard(): void { if (!Number.isInteger(this.cardWeek) || this.cardWeek <= 0) return; this.day = this.cardWeek; this.page = 1; this.cardWeek = 0; this.rebuild(); }
  private scheduleChanged(): void {
    if (!this.visible) return;
    try { this.snapshot = load(this.context()); this.app = loadApp(this.context()); this.loaded = true; this.error = ''; this.rebuild(); }
    catch (_) { this.error = '课表刷新失败，请返回重试，原数据保留'; }
  }
  onPageShow(): void {
    this.visible = true; this.clock = Date.now();
    const card = AppStorage.get<number>('cardWeek') || 0; if (card) { this.day = card; this.page = 1; AppStorage.set('cardWeek', 0); }
    let phase = '课表';
    try { this.snapshot = load(this.context()); phase = '设置'; this.app = loadApp(this.context()); phase = '周页面'; this.loaded = true; this.error = ''; this.rebuild(); }
    catch (e) { hilog.error(0xFF12, 'NuaMain', 'load phase=%{public}s, error=%{public}s', phase, (e as Error).message.slice(0, 160)); this.error = '本地' + phase + '读取失败，原数据已保留，请勿清除应用数据。'; this.loaded = false; }
    if (this.timer < 0) this.timer = setInterval(() => { this.clock = Date.now(); this.presentUpdate(); }, 30000);
    if (this.loaded) { this.refresh(); setTimeout(() => this.emptyPrompt(), 300); }
    if (!this.autoChecked) { this.autoChecked = true; this.softwareUpdate(false); }
    setTimeout(() => this.presentUpdate(), 500);
  }
  onPageHide(): void { this.visible = false; if (this.timer >= 0) clearInterval(this.timer); this.timer = -1; }
  aboutToDisappear(): void { this.onPageHide(); }
  onBackPress(): boolean {
    if (this.detail || this.editing) { this.closeDetail(); return true; }
    if (this.page === 3) { this.selectPage(2); return true; }
    return false;
  }
  private refresh(): void {
    refreshAllForms(this.context()).catch(() => {});
    scheduleReminders(this.context()).then((message: string) => { this.reminderStatus = message; }).catch(() => { this.reminderStatus = '提醒未能注册，请检查通知权限后重试'; });
  }
  private changes(): void {
    try { const lines = pendingChanges(this.context()); if (!lines.length) { this.toast('暂无课表变更记录'); return; }
      this.getUIContext().showAlertDialog({ title: '课表更新内容', message: lines.map((v) => v.kind + '：' + v.text).join('\n'), confirm: { value: '已查看', action: () => acknowledgeChanges(this.context()) } });
    } catch (_) { this.toast('变更记录暂时无法读取'); }
  }
  private commit(): boolean {
    if (!this.loaded) { this.error = '数据未完整读取，已阻止覆盖'; return false; }
    try { saveApp(this.context(), this.app); this.app = JSON.parse(JSON.stringify(this.app)) as AppState; this.rebuild(); this.refresh(); return true; }
    catch (_) { this.error = '保存失败，原数据保留'; try { this.app = loadApp(this.context()); } catch (_) {} return false; }
  }
  private importSchedule(manual: boolean): void { this.getUIContext().getRouter().pushUrl({ url: 'pages/Sync', params: { manual: manual } }); }
  private emptyPrompt(): void {
    if (!this.visible || this.promptHandled || !this.loaded || this.snapshot.rules.length || this.editing || this.detail) return;
    this.promptHandled = true;
    this.promptOpen = true;
    this.getUIContext().showAlertDialog({ title: '先导入你的课表', message: '当前还没有可显示的课表。可登录学校教务系统自动获取，或导入学校导出的 XLS 文件。导入前会显示预览供你确认。',
      autoCancel: false, buttons: [{ value: '登录获取', action: () => { this.promptOpen = false; this.importSchedule(false); } }, { value: '导入 XLS', action: () => { this.promptOpen = false; this.importSchedule(true); } }, { value: '稍后', action: () => { this.promptOpen = false; } }] });
  }
  private selectPage(value: number): void { this.cancelRevision++; this.dragActive = false; this.page = value; }
  private rebuild(): void { this.cancelRevision++; this.weeks = new WeekData(this.snapshot, this.app, this.day); this.weekIndex = 53; }
  private editCourse(day: number, first: number = 1, last: number = 2, id: string = ''): void { this.closeDetail(); this.cancelRevision++; this.getUIContext().getRouter().pushUrl({ url: 'pages/CourseEdit', params: { day: day, first: first, last: last, ruleId: id } }); }
  private editReminder(meeting: Meeting): void { this.closeDetail(); this.getUIContext().getRouter().pushUrl({ url: 'pages/ReminderEdit', params: { day: meeting.day, ruleId: meeting.rule.id } }); }
  private pickDate(kind: string): void {
    const value = kind === 'start' ? this.snapshot.startDate : kind === 'event' ? this.draft.date : dateText(this.day);
    this.getUIContext().showDatePickerDialog({ start: new Date(2020, 0, 1), end: new Date(2040, 11, 31), selected: new Date(Number(value.slice(0, 4)), Number(value.slice(5, 7)) - 1, Number(value.slice(8))),
      onAccept: (result: DatePickerResult) => {
        const text = String(result.year) + '-' + String((result.month ?? 0) + 1).padStart(2, '0') + '-' + String(result.day).padStart(2, '0');
        if (kind === 'event') { this.draft.date = text; this.draft = this.copyEvent(this.draft); }
        else if (kind === 'start') this.getUIContext().showAlertDialog({ title: '确认开学时间', message: text + '\n所在周的周一至周日将作为第1周。', primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '保存', action: () => {
          if (!this.loaded) return;
          const next: Snapshot = { schema: 1, startDate: text, rules: this.snapshot.rules, syncedAt: this.snapshot.syncedAt };
          try { save(this.context(), next); this.snapshot = next; this.rebuild(); this.refresh(); } catch (_) { this.error = '开学时间保存失败'; }
        } } });
        else { this.day = dayNumber(text); this.rebuild(); }
      } });
  }
  private pickTime(end: boolean): void {
    const time = end ? this.draft.end : this.draft.start;
    this.getUIContext().showTimePickerDialog({ selected: new Date(2026, 0, 1, Number(time.slice(0, 2)), Number(time.slice(3))), useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => { const text = String(value.hour).padStart(2, '0') + ':' + String(value.minute).padStart(2, '0'); if (end) this.draft.end = text; else this.draft.start = text; this.draft = this.copyEvent(this.draft); } });
  }
  private copyEvent(e: AgendaEvent): AgendaEvent { return { id: e.id, title: e.title, place: e.place, date: e.date, start: e.start, end: e.end, allDay: e.allDay, done: e.done, remind: e.remind }; }
  private editEvent(event?: AgendaEvent): void {
    this.draft = event ? this.copyEvent(event) : { id: Date.now().toString() + '-' + Math.random().toString(36).slice(2), title: '', place: '', date: dateText(nowDay(this.clock)), start: '09:00', end: '10:00', allDay: false, done: false, remind: false };
    this.formError = ''; this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => { this.editing = true; });
  }
  private saveEvent(): void {
    try { validEvent(this.draft); } catch (_) { this.formError = '请填写标题，并确保结束时间晚于开始时间'; return; }
    const warning = eventConflicts(this.snapshot, this.app, this.draft);
    if (warning.length) { this.getUIContext().showAlertDialog({ title: '日程时间冲突', message: warning.join('\n'), primaryButton: { value: '返回修改', action: () => {} }, secondaryButton: { value: '仍然保存', action: () => this.persistEvent() } }); return; }
    this.persistEvent();
  }
  private persistEvent(): void {
    this.app.events = this.app.events.filter((e: AgendaEvent) => e.id !== this.draft.id).concat([this.copyEvent(this.draft)]);
    if (this.commit()) { this.editing = false; if (this.draft.remind) allowNotifications(this.context()).then(() => this.refresh()).catch(() => { this.reminderStatus = '日程已保存，但通知尚未授权'; }); }
  }
  private eventActions(event: AgendaEvent): void {
    this.getUIContext().showAlertDialog({ title: event.title, message: event.date + ' · ' + (event.allDay ? '全天' : event.start + '–' + event.end) + '\n' + event.place,
      buttons: [{ value: event.done ? '恢复待完成' : '标记完成', action: () => { this.app.events = this.app.events.map((e: AgendaEvent) => { const next = this.copyEvent(e); if (e.id === event.id) next.done = !event.done; return next; }); this.commit(); } }, { value: '编辑', action: () => this.editEvent(event) }, { value: '关闭', action: () => {} }] });
  }
  private showDetail(meeting: Meeting): void { this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => { this.detail = meeting; }); }
  private closeDetail(): void { this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseIn }, () => { this.detail = undefined; this.editing = false; }); setTimeout(() => this.presentUpdate(), 300); }
  private chooseTheme(): void {
    this.getUIContext().showActionSheet({ title: '界面主题', message: '选择应用配色', sheets: ['跟随系统', '浅色', '深色'].map((name: string, index: number): SheetInfo => ({ title: name, action: () => {
      this.app.preferences.theme = index;
      if (this.commit()) { try { this.context().getApplicationContext().setColorMode(index === 2 ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : index === 1 ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET); } catch (_) { this.toast('主题已保存，系统弹窗外观将在下次启动时应用'); } }
    } })) });
  }
  private clearSchedule(): void {
    this.getUIContext().showAlertDialog({ title: '清空课表？', message: '仅删除已导入的课程，保留个人日程和偏好；可以重新导入。', primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '清空', action: () => {
      if (!this.loaded) return; const next: Snapshot = { schema: 1, startDate: this.snapshot.startDate, rules: [], syncedAt: 0 };
      try { save(this.context(), next); this.snapshot = next; this.rebuild(); this.refresh(); } catch (_) { this.error = '清空失败，原课表保留'; }
    } } });
  }
  private async softwareUpdate(manual: boolean): Promise<void> {
    if (this.updating) { if (manual) this.manualWaiting = true; return; }
    this.updating = true; this.manualWaiting = manual;
    try {
      const result = await checkUpdate(this.context(), manual);
      if (result.available) { this.deferredUpdate = result; this.presentUpdate(); }
      else if (this.manualWaiting && this.visible) this.toast(result.message);
    } catch (_) { if (this.manualWaiting && this.visible) this.toast('更新检查失败，请稍后重试'); }
    finally { this.updating = false; this.manualWaiting = false; }
  }
  private presentUpdate(): void {
    if (!this.deferredUpdate || !this.visible || this.promptOpen || this.editing || this.detail || (!this.promptHandled && !this.snapshot.rules.length)) return;
    const result = this.deferredUpdate; this.deferredUpdate = undefined;
    this.getUIContext().showAlertDialog({ title: '发现新版本 ' + result.version, message: result.notes + '\n\n鸿蒙安装通过华为允许的分发渠道，不会下载安卓 APK。', primaryButton: { value: '稍后', action: () => {} }, secondaryButton: { value: '查看更新', action: () => { openUpdate(this.context(), result).catch(() => this.toast('无法打开更新页面')); } } });
  }
  private toast(message: string): void { this.getUIContext().getPromptAction().showToast({ message: message }); }
  private timetable(): Meeting[] { return meetings(this.snapshot, monday(this.day)); }
  private items(): TimelineItem[] { return agenda(this.snapshot, this.app, nowDay(this.clock), this.clock); }
  private timeline(m: Meeting): TimelineItem { return { id: m.key, title: m.rule.course, place: m.rule.room + ' · ' + m.rule.periods, time: m.rule.start + '\n' + m.rule.end, order: m.rule.start, done: courseStatus(m.rule, m.day, this.clock) === '已结束', meeting: m }; }
  private icon(value: string): Resource {
    if (value === '☁') return $r('app.media.ic_ui_cloud');
    if (value === '▤') return $r('app.media.ic_ui_file');
    if (value === '↻') return $r('app.media.ic_ui_update');
    if (value === '▦') return $r('app.media.ic_ui_calendar');
    if (value === '◐') return $r('app.media.ic_ui_theme');
    if (value === '▥' || value === '▣') return $r('app.media.ic_ui_grid');
    if (value === '⌫') return $r('app.media.ic_ui_trash');
    return $r('app.media.ic_ui_settings');
  }
  @Builder private heading(title: string) { Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.primary()).width('100%').margin({ top: 16, bottom: 12 }) }
  @Builder private message(title: string) { Text(title).fontSize(14).fontColor(this.secondary()).width('100%').margin({ top: 10, bottom: 10 }) }
  @Builder private smallButton(title: string, action: () => void) {
    Button(title, { type: ButtonType.Normal }).fontSize(13).fontColor(this.brand()).backgroundColor(this.control()).borderRadius(12).height(44).layoutWeight(1).onClick(action)
  }
  @Builder private actionCard(icon: string, title: string, subtitle: string, badge: string, color: string, main: boolean, action: () => void) {
    Row({ space: 14 }) {
      Image(this.icon(icon)).fillColor(main ? this.onBrand() : color).width(48).height(48).padding(12).backgroundColor(main ? (this.dark() ? '#18102A3E' : '#18FFFFFF') : '#18' + color.slice(1)).borderRadius(14)
      Column({ space: 5 }) {
        Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(main ? this.onBrand() : this.primary()).width('100%')
        Text(subtitle).fontSize(12).fontColor(main ? this.onBrand() : this.secondary()).opacity(main ? 0.88 : 1).width('100%')
        Row() { Text(badge).fontSize(10).fontWeight(FontWeight.Bold).fontColor(main ? this.onBrand() : color).padding({ left: 6, right: 6, top: 3, bottom: 3 }).backgroundColor(main ? (this.dark() ? '#18102A3E' : '#18FFFFFF') : '#18' + color.slice(1)).borderRadius(6); }.width('100%')
      }.layoutWeight(1)
      Text('›').fontSize(26).fontColor(main ? this.onBrand() : this.secondary())
    }.padding(18).width('100%').backgroundColor(main ? this.brand() : this.surface()).borderRadius(22).border({ width: main ? 0 : 1, color: this.dark() ? '#3D5263' : '#C6D5DF' }).margin({ bottom: 12 }).accessibilityGroup(true).accessibilityText(title + '，' + subtitle + '，' + badge).onClick(action)
  }
  @Builder private importActions() {
    this.actionCard('☁', '登录并获取课表', '打开学校官方登录页，登录后自动获取', '教务同步', this.brand(), true, () => this.importSchedule(false))
    this.actionCard('▤', '导入 XLS 课表', '使用学校导出的文件，无需网页登录', '本地文件', this.dark() ? '#7BD9B8' : '#08785B', false, () => this.importSchedule(true))
  }
  @Builder private timelineCard(item: TimelineItem) {
    Row({ space: 14 }) {
      Text(item.time).fontSize(12).fontColor(this.secondary()).width(58).textAlign(TextAlign.Center)
      Rect().width(3).height(48).fill(item.done ? this.secondary() : this.brand()).radius(2)
      Column({ space: 8 }) {
        Text(item.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.primary()).width('100%')
        Text(item.place).fontSize(13).fontColor(this.secondary()).width('100%')
      }.layoutWeight(1)
      Text(item.meeting ? '课程' : '日程').fontSize(11).fontColor(this.secondary())
    }.padding({ left: 12, right: 12, top: 18, bottom: 18 }).width('100%').backgroundColor(this.surface()).borderRadius(18).margin({ bottom: 10 }).opacity(item.done ? 0.55 : 1)
      .onClick(() => { if (item.meeting) this.showDetail(item.meeting); else if (item.event) this.eventActions(item.event); })
  }
  @Builder private timetablePage() {
    Swiper() {
      LazyForEach(this.weeks, (data: WeekPage) => {
        WeekBoard({ data: data, dark: this.dark(), grid: this.app.preferences.grid, cancelRevision: this.cancelRevision,
          onCourse: (m: Meeting) => this.showDetail(m), onEvent: (e: AgendaEvent) => this.eventActions(e),
          onNew: (day: number, first: number, last: number) => this.editCourse(day, first, last),
          onDrag: (dragging: boolean) => { this.dragActive = dragging; }
        })
      }, (data: WeekPage) => data.key)
    }.index(this.weekIndex).loop(false).indicator(false).itemSpace(0).cachedCount(2).duration(240).curve(Curve.EaseOut).disableSwipe(this.dragActive)
      .onChange((index: number) => { this.cancelRevision++; this.weekIndex = index; this.day = this.weeks.dayAt(index) + weekday(this.day) - 1; })
      .layoutWeight(1).width('100%')
  }
  @Builder private agendaPage() {
    Button('＋ 添加日程', { type: ButtonType.Normal }).width('100%').height(48).fontColor(this.brand()).backgroundColor(this.control()).borderRadius(14).onClick(() => this.editEvent())
    this.message(countdown(this.snapshot, this.clock))
    if (conflictsToday(this.snapshot, this.app, nowDay(this.clock), this.clock).length) { this.heading('时间冲突'); ForEach(conflictsToday(this.snapshot, this.app, nowDay(this.clock), this.clock), (text: string) => { Text('⚠ ' + text).fontSize(14).fontColor(this.dark() ? '#FFD48B' : '#9B5C00').width('100%').padding(12).backgroundColor(this.control()).borderRadius(12).margin({ bottom: 8 }); }) }
    this.heading('待完成（' + this.items().filter((item: TimelineItem) => !item.done).length + '）')
    ForEach(this.items().filter((item: TimelineItem) => !item.done), (item: TimelineItem) => { this.timelineCard(item) }, (item: TimelineItem) => item.id)
    if (!this.items().some((item: TimelineItem) => !item.done)) { this.message('当天没有待完成事项'); }
    Text('已完成（' + this.items().filter((item: TimelineItem) => item.done).length + '） ' + (this.expanded ? '⌃' : '⌄')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.primary()).width('100%').padding({ top: 16, bottom: 12 }).onClick(() => { this.expanded = !this.expanded; })
    if (this.expanded) { ForEach(this.items().filter((item: TimelineItem) => item.done), (item: TimelineItem) => { this.timelineCard(item) }, (item: TimelineItem) => item.id) }
    this.heading('其他日期的个人日程')
    ForEach(this.app.events.filter((e: AgendaEvent) => e.date !== dateText(nowDay(this.clock))).sort((a: AgendaEvent, b: AgendaEvent) => a.date.localeCompare(b.date) || a.start.localeCompare(b.start)), (e: AgendaEvent) => { this.timelineCard({ id: e.id, title: e.title, place: e.place, time: e.date.slice(5) + '\n' + (e.allDay ? '全天' : e.start), order: e.date + e.start, done: e.done, event: e }); }, (e: AgendaEvent) => e.id)
  }
  @Builder private minePage() {
    Column({ space: 10 }) {
      Text(this.snapshot.rules.length ? '课表已就绪' : '等待导入课表').fontSize(23).fontWeight(FontWeight.Bold).fontColor(this.primary()).width('100%')
      Text(this.snapshot.rules.length ? this.snapshot.rules.length + ' 个上课安排 · 开学时间 ' + this.snapshot.startDate : '同步教务课表，或导入已下载的 XLS 文件').fontSize(14).fontColor(this.secondary()).width('100%')
      Text(this.snapshot.syncedAt ? '最近导入 ' + new Date(this.snapshot.syncedAt).toLocaleString() : '数据保存在本机 · 导入前可预览确认').fontSize(12).fontColor(this.secondary()).width('100%')
    }.padding(24).width('100%').backgroundColor(this.dark() ? '#223849' : '#EAF3F8').borderRadius(24)
    this.heading('课表来源'); this.importActions(); this.heading('偏好与应用')
    this.actionCard('▤', '课表变更记录', '只有课程内容变化才记录，通知不包含课程详情', '更新预览', this.brand(), false, () => this.changes())
    this.actionCard('⚙', '课表与界面设置', '开学时间、显示模式、主题、卡片与提醒', '个性化', this.dark() ? '#C5ADFF' : '#6B49B9', false, () => this.selectPage(3))
    this.actionCard('↻', this.updating ? '正在检查更新' : '检查软件更新', '打开 App 自动检查，也可点此手动检查', '应用更新', this.dark() ? '#FFD48B' : '#966300', false, () => this.softwareUpdate(true))
    this.message('南艺电子课表 · 1.2.4 HarmonyOS\n没有会员或广告。只有主动获取课表才打开学校登录；软件更新仅在打开 App 时检查。\n非学校官方应用。')
  }
  @Builder private settingsPage() {
    this.actionCard('◷', '全局节次时间', '调整第1—12节，课程、提醒和卡片同步使用', '作息时间', this.brand(), false, () => this.getUIContext().getRouter().pushUrl({ url: 'pages/PeriodTimes' }))
    this.actionCard('▦', '开学时间：' + this.snapshot.startDate, '选择日期所在周作为第1周', '学期设置', this.brand(), false, () => this.pickDate('start'))
    this.actionCard('◐', '界面主题：' + ['跟随系统', '浅色', '深色'][this.app.preferences.theme], '浅色与深色均沿用安卓版配色', '外观', this.brand(), false, () => this.chooseTheme())
    this.actionCard('▥', '课表展示：' + (this.app.preferences.grid ? '竖条周课表' : '列表课表'), '两种模式都支持左右滑动切换周次', '展示', this.brand(), false, () => { this.app.preferences.grid = !this.app.preferences.grid; this.commit(); })
    Column({ space: 14 }) {
      Row() { Text('开启上课提醒').fontSize(17).fontColor(this.primary()).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.app.preferences.reminders }).onChange((value: boolean) => { this.app.preferences.reminders = value; if (this.commit() && value) allowNotifications(this.context()).then(() => this.refresh()).catch(() => { this.reminderStatus = '通知尚未授权'; }); }); }
      Row() { Text('提醒时间').fontSize(14).fontColor(this.secondary()).layoutWeight(1); Select([{ value: '提前5分钟' }, { value: '提前10分钟' }, { value: '提前15分钟' }, { value: '提前20分钟' }, { value: '提前30分钟' }]).selected([5, 10, 15, 20, 30].indexOf(this.app.preferences.minutes)).value('提前' + this.app.preferences.minutes + '分钟').onSelect((index: number) => { this.app.preferences.minutes = [5, 10, 15, 20, 30][index]; this.commit(); }); }
      Text(this.reminderStatus + '\n系统代理最近30条提醒，每次打开/导入/编辑时补充；省电、权限、强制停止仍可能影响通知。').fontSize(12).fontColor(this.secondary()).width('100%')
      Button('授权通知 / 刷新提醒').fontSize(13).fontColor(this.brand()).backgroundColor(this.control()).onClick(() => allowNotifications(this.context()).then(() => this.refresh()).catch(() => this.toast('请到系统设置允许本应用通知')))
    }.padding(18).width('100%').backgroundColor(this.surface()).borderRadius(20).margin({ bottom: 12 })
    this.actionCard('▤', '导出与备份', 'JSON 备份、XLS 表格、ICS 日历与恢复', '本地文件', this.brand(), false, () => this.getUIContext().getRouter().pushUrl({ url: 'pages/Transfer' }))
    Row() { Text('调试模式').fontColor(this.primary()).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.app.preferences.debug || false }).onChange((v: boolean) => { this.app.preferences.debug = v; this.commit(); }); }.padding(18).backgroundColor(this.surface()).borderRadius(18).margin({ bottom: 12 })
    if (this.app.preferences.debug) { this.actionCard('▣', '桌面卡片诊断', '仅记录刷新结果与操作类型，不含账号或课程内容', '调试', this.brand(), false, () => { try { this.getUIContext().showAlertDialog({ title: '卡片诊断', message: (JSON.parse(readJson(this.context(), 'form-diagnostics.json', '[]')) as string[]).join('\n') || '暂无记录', confirm: { value: '关闭', action: () => {} } }); } catch (_) { this.toast('诊断不可用'); } }); }
    Row() { Text('提醒方式').fontColor(this.primary()).layoutWeight(1); Select([{ value: '通知' }, { value: '闹钟' }]).selected(this.app.preferences.reminderMode === 2 ? 1 : 0).value(this.app.preferences.reminderMode === 2 ? '闹钟' : '通知').onSelect((i: number) => { this.app.preferences.reminderMode = i + 1; this.commit(); }); }.padding(18).backgroundColor(this.surface()).borderRadius(18)
    Row() { Text('仅提醒选中的课程').fontColor(this.primary()).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.app.preferences.selectedOnly || false }).onChange((v: boolean) => { this.app.preferences.selectedOnly = v; this.commit(); }); }.padding(18)
    if (this.app.preferences.selectedOnly) { ForEach(Array.from(new Set<string>(this.snapshot.rules.map((r) => r.course))), (name: string) => { Row() { Checkbox().select((this.app.preferences.selectedCourses || []).includes(name)).onChange((v: boolean) => { this.app.preferences.selectedCourses = (this.app.preferences.selectedCourses || []).filter((s: string) => s !== name); if (v) this.app.preferences.selectedCourses.push(name); this.commit(); }); Text(name).fontColor(this.primary()).layoutWeight(1); }.padding(8) }) }
    this.actionCard('⚙', '通知与省电说明', '允许通知、检查启动管理，让课表提醒更稳定', '系统设置', this.brand(), false, () => this.getUIContext().showAlertDialog({ title: '提醒与卡片设置', message: '请在系统设置中找到本应用，允许发送通知；如设备提供应用启动管理或省电限制，请允许必要的后台活动。\n鸿蒙系统仍会管理卡片刷新配额，本应用不会申请系统专用权限或保持网页登录。', confirm: { value: '知道了', action: () => {} } }))
    this.actionCard('▣', '添加桌面卡片', '列表、竖条周课表 · 各有深色与白色', '服务卡片', this.brand(), false, () => this.getUIContext().showAlertDialog({ title: '添加桌面课表卡片', message: '在桌面长按“南艺电子课表”图标 → 服务卡片 → 选择列表或竖条周课表，再选择深色或白色添加。卡片刷新由系统调度，点击↻可主动刷新。', confirm: { value: '知道了', action: () => {} } }))
    this.actionCard('▤', '手动导入 XLS', '教务自动获取失败时的备用入口', '本地导入', this.brand(), false, () => this.importSchedule(true))
    if (this.snapshot.rules.length) { this.actionCard('⌫', '清空课表', '保留日程和设置，恢复空课表', '谨慎操作', this.dark() ? '#FFA3AB' : '#BC3045', false, () => this.clearSchedule()); }
  }
  @Builder private detailSheet() {
    if (this.detail) {
      Scroll() {
      Column({ space: 20 }) {
        Text(this.detail.rule.course).fontSize(23).fontWeight(FontWeight.Bold).fontColor(this.primary()).width('100%')
        Text(dateText(this.detail.day) + '\n\n' + this.detail.rule.start + '–' + this.detail.rule.end + ' · ' + this.detail.rule.periods + '\n\n地点：' + this.detail.rule.room + '\n\n教师：' + this.detail.rule.teacher + '\n\n' + this.detail.rule.type + ' · ' + courseStatus(this.detail.rule, this.detail.day, this.clock)).fontSize(16).fontColor(this.secondary()).width('100%')
        if (this.detail.rule.credits || this.detail.rule.note) { Text('学分：' + (this.detail.rule.credits || '未填写') + '\n' + (this.detail.rule.note || '')).fontSize(14).fontColor(this.secondary()).width('100%'); }
        Row({ space: 10 }) { this.smallButton('编辑这个时段', () => { if (this.detail) this.editCourse(this.detail.day, 1, 2, this.detail.rule.id || ''); }); this.smallButton('单独提醒', () => { if (this.detail) this.editReminder(this.detail); }); }
        Button('收起详情', { type: ButtonType.Normal }).width('100%').height(46).fontColor(this.brand()).backgroundColor(this.control()).borderRadius(14).onClick(() => this.closeDetail())
      }.padding(24).width('100%')
      }.width('92%').constraintSize({ maxHeight: '66%' }).backgroundColor(this.surface()).borderRadius(24).margin({ top: 12 }).transition(TransitionEffect.move(TransitionEdge.TOP)).onClick(() => {})
    }
  }
  @Builder private eventSheet() {
    Scroll() {
      Column({ space: 16 }) {
        Text(this.app.events.some((e: AgendaEvent) => e.id === this.draft.id) ? '编辑日程' : '添加日程').fontSize(23).fontWeight(FontWeight.Bold).fontColor(this.primary()).width('100%')
        TextInput({ text: this.draft.title, placeholder: '日程标题（必填，最多80字）' }).maxLength(80).fontColor(this.primary()).backgroundColor(this.control()).onChange((value: string) => { this.draft.title = value; })
        TextInput({ text: this.draft.place, placeholder: '地点（可选）' }).maxLength(200).fontColor(this.primary()).backgroundColor(this.control()).onChange((value: string) => { this.draft.place = value; })
        Button('日期：' + this.draft.date).fontColor(this.brand()).backgroundColor(this.control()).width('100%').onClick(() => this.pickDate('event'))
        Row() { Text('全天日程').fontColor(this.primary()).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.draft.allDay }).onChange((value: boolean) => { this.draft.allDay = value; this.draft = this.copyEvent(this.draft); }); }
        if (!this.draft.allDay) { Row({ space: 8 }) { this.smallButton('开始：' + this.draft.start, () => this.pickTime(false)); this.smallButton('结束：' + this.draft.end, () => this.pickTime(true)); } }
        Row() { Text('提前15分钟提醒\n全天日程为当日09:00').fontSize(13).fontColor(this.secondary()).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.draft.remind }).onChange((value: boolean) => { this.draft.remind = value; }); }
        if (this.formError) { Text(this.formError).fontColor('#BC3045').fontSize(13); }
        Button('保存日程', { type: ButtonType.Normal }).width('100%').height(46).fontColor(this.dark() ? '#102A3E' : '#FFFFFF').backgroundColor(this.brand()).borderRadius(14).onClick(() => this.saveEvent())
        if (this.app.events.some((e: AgendaEvent) => e.id === this.draft.id)) {
          Button('删除日程').fontColor('#BC3045').backgroundColor(this.control()).onClick(() => this.getUIContext().showAlertDialog({ title: '删除这条日程？', message: '删除后不可恢复。', primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '删除', action: () => { this.app.events = this.app.events.filter((e: AgendaEvent) => e.id !== this.draft.id); if (this.commit()) this.editing = false; } } }))
        }
        Button('取消').fontColor(this.brand()).backgroundColor(this.control()).onClick(() => this.closeDetail())
      }.padding(24).width('100%')
    }.width('92%').constraintSize({ maxHeight: '85%' }).backgroundColor(this.surface()).borderRadius(24).margin({ top: 12 }).transition(TransitionEffect.move(TransitionEdge.TOP)).onClick(() => {})
  }
  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        Column({ space: 6 }) {
          Row() {
            Text(this.page === 2 ? '我的' : this.page === 3 ? '课表与界面设置' : dateText(this.page === 0 ? nowDay(this.clock) : this.day).replace(/-/g, '/') + ' 周' + '一二三四五六日'.charAt(weekday(this.page === 0 ? nowDay(this.clock) : this.day) - 1)).fontSize(25).fontWeight(FontWeight.Bold).fontColor(this.primary()).layoutWeight(1).onClick(() => { if (this.page === 1) this.pickDate('day'); })
            if (this.page === 3) { Button('返回').fontColor(this.brand()).backgroundColor(this.control()).onClick(() => this.selectPage(2)); }
          }.width('100%').constraintSize({ minHeight: 44 })
          Text(this.page === 1 ? '第' + week(this.day, this.snapshot.startDate) + '周 · ' + (this.app.preferences.grid ? '竖条课表' : '列表课表') : this.page === 0 ? '当天课程与个人事项' : '南艺电子课表 · 数据保存在本机').fontSize(13).fontColor(this.secondary()).width('100%')
          if (this.page === 1) {
            Row({ space: 8 }) { this.smallButton('选择日期', () => this.pickDate('day')); this.smallButton('＋ 添加课程', () => this.editCourse(this.day)); }.margin({ top: 8 })
            Button(this.app.preferences.grid ? '竖条课表 · 切换为列表' : '列表课表 · 切换为竖条', { type: ButtonType.Normal }).width('100%').height(44).fontColor(this.brand()).backgroundColor(this.control()).borderRadius(12).margin({ top: 4 }).onClick(() => { this.app.preferences.grid = !this.app.preferences.grid; this.commit(); })
          }
        }.padding({ left: 20, right: 20, top: 16 }).width('100%')
        if (this.page === 1) { this.timetablePage(); }
        else { Scroll(this.scroller) {
          Column() {
            if (this.error) { Text(this.error).fontSize(14).fontColor('#BC3045').width('100%'); }
            if (this.page === 0) { this.agendaPage(); } else if (this.page === 2) { this.minePage(); } else { this.settingsPage(); }
          }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').align(Alignment.TopStart)
        }
        if (this.page !== 3) {
          Row() {
            ForEach(['日程', '课表', '我的'], (name: string, index: number) => { Text(name).fontSize(18).fontWeight(this.page === index ? FontWeight.Bold : FontWeight.Normal).fontColor(this.page === index ? this.brand() : this.secondary()).height(56).layoutWeight(1).textAlign(TextAlign.Center).onClick(() => this.selectPage(index)) })
          }.width('100%').backgroundColor(this.surface()).padding({ bottom: 6 })
        }
      }.width('100%').height('100%').backgroundColor(this.bg())
      if (this.detail || this.editing) {
        Stack({ alignContent: Alignment.Top }) { Rect().width('100%').height('100%').fill('#48000000').onClick(() => this.closeDetail()); if (this.detail) { this.detailSheet(); } else { this.eventSheet(); } }.width('100%').height('100%')
      }
    }.width('100%').height('100%')
  }
}
