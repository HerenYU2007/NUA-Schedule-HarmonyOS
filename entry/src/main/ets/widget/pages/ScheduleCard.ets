import { CardLine } from '../../model/Schedule';
import { WeekCardBlock } from '../../model/CardModel';
import { dailyCardCapacity } from '../../model/CardLayout';
const storage: LocalStorage = new LocalStorage();
@Entry(storage)
@Component
struct ScheduleCard {
  @LocalStorageProp('title') title: string = '今日课表';
  @LocalStorageProp('subtitle') subtitle: string = '';
  @LocalStorageProp('lines') lines: CardLine[] = [];
  @LocalStorageProp('empty') empty: string = '点此打开应用';
  @LocalStorageProp('overflow') overflow: string = '';
  @LocalStorageProp('next') next: string = '';
  @LocalStorageProp('availableHeight') availableHeight: number = 180;
  @LocalStorageProp('white') white: boolean = false;
  @LocalStorageProp('kind') kind: string = 'daily';
  @LocalStorageProp('weekDay') weekDay: number = 0;
  @LocalStorageProp('weekBlocks') weekBlocks: WeekCardBlock[] = [];
  @LocalStorageProp('dates') dates: string[] = [];
  private ink(): string { return this.white ? '#243746' : '#FFFFFF'; }
  private accent(): string { return this.white ? '#1F4E78' : '#A9D8FA'; }
  private secondary(): string { return this.white ? '#5B6B78' : '#D1DFEA'; }
  private unit(): number { return Math.max(12, (this.availableHeight - 104) / 12); }
  private open(): void { postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { cardWeek: this.kind === 'week' ? this.weekDay : 0 } }); }
  private compact(): boolean { return this.availableHeight < 240; }
  private capacity(): number { return dailyCardCapacity(this.availableHeight); }
  private remaining(): string {
    const match = this.overflow.match(/还有(\d+)节/);
    const count = Math.max(0, this.lines.length - this.capacity()) + (match ? Number(match[1]) : 0);
    return count > 0 ? '还有' + count + '节课 · 点此查看' : this.overflow;
  }
  private caption(): string {
    const next = this.next || this.subtitle;
    return this.compact() && this.remaining() ? this.remaining() + ' · ' + next : next;
  }
  @Builder private weekly() {
    Row() {
      Text('‹ 上周').fontSize(11).fontColor(this.accent()).padding(8).onClick(() => postCardAction(this, { action: 'message', params: { command: 'previousWeek' } }))
      Text(this.title).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.ink()).layoutWeight(1).textAlign(TextAlign.Center).maxLines(1).onClick(() => postCardAction(this, { action: 'message', params: { command: 'currentWeek' } }))
      Text('下周 ›').fontSize(11).fontColor(this.accent()).padding(8).onClick(() => postCardAction(this, { action: 'message', params: { command: 'nextWeek' } }))
    }.width('100%')
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 0 }) {
        Row() { Text('节').fontSize(9).fontColor(this.secondary()).width(18); ForEach(this.dates, (d: string) => { Text(d).fontSize(10).fontColor(this.secondary()).textAlign(TextAlign.Center).layoutWeight(1).height(30); }); }.width('100%')
        ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], (p: number) => { Row() { Text(String(p)).fontSize(9).fontColor(this.secondary()).width(18); Blank(); }.height(this.unit()).width('100%').border({ width: { top: 0.3 }, color: this.white ? '#DAE5ED' : '#39546A' }); })
      }.width('100%')
      ForEach(this.weekBlocks, (b: WeekCardBlock) => {
        Text(b.label).fontSize(10).fontColor(this.ink()).fontWeight(FontWeight.Medium).align(Alignment.TopStart).padding(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('13.1%').height(Math.max(12, (b.last - b.first) * this.unit() - 2))
          .backgroundColor(this.white ? '#D8EAF8' : '#345B78').borderRadius(4)
          .position({ x: (5.4 + b.day * 94.6 / 7) + '%', y: 30 + b.first * this.unit() + 1 })
      }, (b: WeekCardBlock) => b.id)
      if (!this.weekBlocks.length) { Text(this.empty).fontSize(13).fontColor(this.secondary()).padding({ top: 60 }).width('100%').textAlign(TextAlign.Center); }
    }.width('100%').layoutWeight(1).onClick(() => this.open())
    Text('点击中间回到本周 · 点课程查看详情').fontSize(9).fontColor(this.secondary()).maxLines(1)
  }
  build() {
    Column({ space: this.compact() && this.kind !== 'week' ? 3 : 6 }) {
      if (this.kind === 'week') { this.weekly(); } else {
      Row() {
        Text(this.title).fontSize(this.compact() ? 15 : 17).lineHeight(this.compact() ? 20 : 23).fontWeight(FontWeight.Bold).fontColor(this.ink()).layoutWeight(1).maxLines(1)
        Text('‹ 今').fontSize(this.compact() ? 11 : 13).lineHeight(this.compact() ? 16 : 20).fontColor(this.accent()).padding(4)
          .onClick(() => postCardAction(this, { action: 'message', params: { command: 'today' } }))
        Text('明 ›').fontSize(this.compact() ? 11 : 13).lineHeight(this.compact() ? 16 : 20).fontColor(this.accent()).padding(4)
          .onClick(() => postCardAction(this, { action: 'message', params: { command: 'tomorrow' } }))
        Text('↻').fontSize(17).lineHeight(20).fontColor(this.accent()).padding(this.compact() ? 2 : 4)
          .onClick(() => postCardAction(this, { action: 'message', params: { command: 'refresh' } }))
      }.width('100%').height(this.compact() ? 24 : 28)
      Text(this.caption()).fontSize(10).lineHeight(12).fontColor(this.secondary()).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).onClick(() => this.open())
      Column({ space: this.compact() ? 4 : 5 }) {
        ForEach(this.lines.slice(0, this.capacity()), (line: CardLine) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(line.time).fontSize(this.compact() ? 14 : 16).lineHeight(this.compact() ? 17 : 20).fontWeight(FontWeight.Bold).fontColor(this.accent()).width('100%').maxLines(1)
              if (this.compact()) {
                Row({ space: 6 }) {
                  Text(line.course).fontSize(12).lineHeight(15).fontColor(this.ink()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  Text(line.room).fontSize(10).lineHeight(15).fontColor(this.secondary()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 78 })
                }.width('100%')
              } else {
                Text(line.course).fontSize(13).fontColor(this.ink()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(line.room).fontSize(11).fontColor(this.secondary()).width('100%').maxLines(1)
              }
            }.layoutWeight(1)
            Text(line.status).fontSize(10).fontColor(this.accent()).width(48).textAlign(TextAlign.Center)
          }.width('100%').padding(this.compact() ? 4 : 8).borderRadius(10).backgroundColor(this.white ? '#EDF3F8' : '#344F64')
            .onClick(() => this.open())
        })
        if (this.lines.length === 0) {
          Text(this.empty).fontSize(13).fontColor(this.secondary()).padding({ top: 16 }).width('100%')
            .onClick(() => this.open())
        }
        if (this.remaining() && !this.compact()) {
          Text(this.remaining()).fontSize(10).fontColor(this.accent()).maxLines(1)
            .onClick(() => this.open())
        }
      }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start)
      }
    // Fill the host surface: its own clipping supplies the system corner radius.
    }.padding(this.kind === 'week' ? 8 : this.compact() ? 6 : 12).width('100%').height('100%').backgroundColor(this.white ? '#FFFFFF' : '#20394D').clip(true)
  }
}
