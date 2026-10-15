import { Snapshot, dateText, nowDay, weekday } from '../model/Schedule';
import { AppState, Meeting, TimelineItem, AgendaEvent, defaultState, courseColor } from '../model/AppModel';
import { WeekPage, BoardBlock, freeCell, dragSpan, ruleTint } from '../model/Parity';
import { PERIOD_START, PERIOD_END } from '../model/SchoolClock';
import { pageFree } from '../model/Occupancy';
@Component
export struct WeekBoard {
  @Prop data: WeekPage;
  @Prop dark: boolean = false;
  @Prop grid: boolean = false;
  @Prop @Watch('cancelled') cancelRevision: number = 0;
  private cancelled(): void { this.clear(); }
  onCourse: (value: Meeting) => void = () => {};
  onEvent: (value: AgendaEvent) => void = () => {};
  onNew: (day: number, first: number, last: number) => void = () => {};
  onDrag: (dragging: boolean) => void = () => {};
  @State boardWidth: number = 320;
  @State draftDay: number = -1;
  @State first: number = 1;
  @State last: number = 1;
  private startFirst: number = 1;
  private startLast: number = 1;
  private startScroll: number = 0;
  private viewportTop: number = 0;
  private viewportHeight: number = 400;
  private scroller: Scroller = new Scroller();
  private ink(): string { return this.dark ? '#E8EFF5' : '#243746'; }
  private surface(): string { return this.dark ? '#1C2833' : '#FFFFFF'; }
  private col(): number { return Math.max(1, (this.boardWidth - 42) / 7); }
  private clear(): void { this.draftDay = -1; this.onDrag(false); }
  private cell(day: number, period: number): void {
    if (this.draftDay >= 0) { this.clear(); return; }
    if (!pageFree(this.data, day, period, period)) return;
    this.draftDay = day; this.first = period; this.last = period;
  }
  private block(block: BoardBlock): void {
    this.clear();
    if (block.event) { this.onEvent(block.event); return; }
    if (block.meetings.length === 1) { this.onCourse(block.meetings[0]); return; }
    this.getUIContext().showActionSheet({ title: '同一位置有多节课', message: '请选择要查看的课程', sheets: block.meetings.map((m: Meeting): SheetInfo => ({ title: m.rule.course + ' · ' + m.rule.start + ' · ' + m.rule.room, action: () => this.onCourse(m) })) });
  }
  private label(block: BoardBlock): string {
    if (block.event) return '日程\n' + block.event.title + '\n@' + block.event.place;
    const main = block.meetings[0]; return main.rule.course + '\n@' + main.rule.room + (block.meetings.length > 1 ? '\n共' + block.meetings.length + '节 · 点开' : '') + (block.conflicts ? '\n⚠ 重叠' : '');
  }
  private tint(block: BoardBlock): string { return block.event ? (this.dark ? '#595331' : '#F9DF9B') : ruleTint(block.meetings[0].rule, courseColor(block.meetings[0].rule.course, this.dark), this.dark); }
  private beginDrag(): void { this.startFirst = this.first; this.startLast = this.last; this.startScroll = this.scroller.currentOffset().yOffset; this.onDrag(true); }
  private drag(event: GestureEvent, edge: number): void {
    const next = dragSpan(this.startFirst, this.startLast, Math.round((event.offsetY + this.scroller.currentOffset().yOffset - this.startScroll) / 80), edge);
    if (pageFree(this.data, this.draftDay, next[0], next[1])) { this.first = next[0]; this.last = next[1]; }
    const global = event.fingerList[0]?.globalY ?? (this.viewportTop + 100);
    if (global < this.viewportTop + 36) this.scroller.scrollBy(0, -12);
    if (global > this.viewportTop + this.viewportHeight - 36) this.scroller.scrollBy(0, 12);
  }
  @Builder private handle(edge: number) {
    Text(edge < 0 ? '⌃' : '⌄').fontSize(this.first === this.last ? 13 : 18).fontColor('#FFFFFF').textAlign(TextAlign.Center).width('100%').height(this.first === this.last ? 18 : 24).maxLines(1).clip(true).backgroundColor('#1F4E78')
      .gesture(PanGesture({ direction: PanDirection.Vertical, distance: 3 }).onActionStart(() => this.beginDrag()).onActionUpdate((e: GestureEvent) => this.drag(e, edge)).onActionEnd(() => this.onDrag(false)).onActionCancel(() => this.onDrag(false)))
  }
  @Builder private board() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 0 }) {
        Row({ space: 0 }) {
          Text('节次').width(42).fontSize(11).fontColor(this.ink()).height(48).textAlign(TextAlign.Center).onClick(() => this.clear())
          ForEach([0, 1, 2, 3, 4, 5, 6], (i: number) => {
            Text('一二三四五六日'.charAt(i) + '\n' + dateText(this.data.day + i).slice(5).replace('-', '/')).fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.ink()).textAlign(TextAlign.Center).height(48).layoutWeight(1).backgroundColor(this.data.day + i === nowDay() ? (this.dark ? '#314E66' : '#DBEDF9') : this.surface()).onClick(() => this.clear())
          })
        }.width('100%')
        ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], (p: number) => {
          Row({ space: 0 }) {
            Text(p + '\n' + PERIOD_START[p] + '\n' + PERIOD_END[p]).fontSize(10).fontColor(this.ink()).width(42).height(80).textAlign(TextAlign.Center).onClick(() => this.clear())
            ForEach([0, 1, 2, 3, 4, 5, 6], (i: number) => { Column().height(80).layoutWeight(1).border({ width: { top: 0.5, left: 0.3 }, color: this.dark ? '#3D5263' : '#D5E0E8' }).onClick(() => this.cell(this.data.day + i, p)) })
          }.width('100%')
        })
      }.width('100%')
      ForEach(this.data.blocks, (b: BoardBlock) => {
        Text(this.label(b)).fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.ink()).align(Alignment.TopStart).padding(4).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(Math.max(1, this.col() - 4)).height(Math.max(28, (b.last - b.first) * 80 - 4)).backgroundColor(this.tint(b)).borderRadius(7)
          .position({ x: 42 + (b.day - this.data.day) * this.col() + 2, y: 48 + b.first * 80 + 2 }).onClick(() => this.block(b))
      }, (b: BoardBlock) => b.id)
      if (this.draftDay >= 0) {
        Column({ space: 0 }) {
          this.handle(-1)
          Text('点击编辑').fontSize(10).lineHeight(12).fontColor('#1F4E78').textAlign(TextAlign.Center).width('100%').layoutWeight(1).constraintSize({ minHeight: 0 }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).clip(true)
            .onClick(() => { const date = this.draftDay, a = this.first, b = this.last; this.clear(); this.onNew(date, a, b); })
            .gesture(PanGesture({ direction: PanDirection.Vertical, distance: 4 }).onActionStart(() => this.beginDrag()).onActionUpdate((e: GestureEvent) => this.drag(e, 0)).onActionEnd(() => this.onDrag(false)).onActionCancel(() => this.onDrag(false)))
          this.handle(1)
        }.width(Math.max(1, this.col() - 4)).height((this.last - this.first + 1) * 80 - 4).backgroundColor('#D8ECFF').border({ width: 2, color: '#1F4E78' }).borderRadius(7).clip(true).position({ x: 42 + (this.draftDay - this.data.day) * this.col() + 2, y: 48 + (this.first - 1) * 80 + 2 })
      }
    }.width('100%').height(1008).backgroundColor(this.surface()).onAreaChange((_old: Area, area: Area) => { this.boardWidth = Number(area.width); })
  }
  @Builder private lesson(m: Meeting) {
    Row({ space: 12 }) {
      Text(m.rule.start + '\n' + m.rule.end).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.ink()).width(58)
      Column({ space: 6 }) { Text(m.rule.course).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.ink()).width('100%'); Text(m.rule.room + ' · ' + m.rule.periods).fontSize(13).fontColor(this.ink()).opacity(0.7).width('100%'); }.layoutWeight(1)
    }.width('100%').padding(18).backgroundColor(this.surface()).borderRadius(18).margin({ bottom: 10 }).onClick(() => { this.clear(); this.onCourse(m); })
  }
  @Builder private outside(item: TimelineItem) {
    Column({ space: 8 }) { Text(item.title).fontSize(17).fontColor(this.ink()).fontWeight(FontWeight.Bold).width('100%'); Text(item.time + '\n' + item.place).fontSize(13).fontColor(this.ink()).opacity(0.7).width('100%'); }.padding(18).width('100%').backgroundColor(this.surface()).borderRadius(18).margin({ top: 10 }).onClick(() => { this.clear(); if (item.meeting) this.onCourse(item.meeting); else if (item.event) this.onEvent(item.event); })
  }
  build() {
    Scroll(this.scroller) {
      Column() {
        if (this.grid) {
          this.board()
          if (this.data.outside.length) { Text('日程与其他安排 · 冲突项目单列显示').fontSize(13).fontColor(this.ink()).width('100%').margin({ top: 16 }); ForEach(this.data.outside, (item: TimelineItem) => { this.outside(item) }, (item: TimelineItem) => item.id) }
        } else {
          ForEach([0, 1, 2, 3, 4, 5, 6], (i: number) => {
            Text(dateText(this.data.day + i).slice(5).replace('-', '/') + ' 周' + '一二三四五六日'.charAt(i)).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink()).width('100%').margin({ top: 16, bottom: 10 })
            ForEach(this.data.meetings.filter((m: Meeting) => m.day === this.data.day + i), (m: Meeting) => { this.lesson(m) }, (m: Meeting) => m.key)
            ForEach(this.data.events.filter((e: AgendaEvent) => e.date === dateText(this.data.day + i)), (e: AgendaEvent) => { this.outside({ id: e.id, title: e.title, place: e.place, time: e.allDay ? '全天' : e.start + '—' + e.end, order: e.start, done: e.done, event: e }) }, (e: AgendaEvent) => e.id)
          })
        }
      }.padding({ left: 16, right: 16, bottom: 20 }).width('100%')
    }.width('100%').height('100%').scrollBar(BarState.Off).onAreaChange((_old: Area, area: Area) => { this.viewportTop = Number(area.globalPosition.y); this.viewportHeight = Number(area.height); })
  }
}
