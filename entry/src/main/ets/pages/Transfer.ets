import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util, taskpool } from '@kit.ArkTS';
import { load } from '../services/Store';
import { loadApp } from '../services/AppStore';
import { backupText, parseBackup, Restored } from '../model/ExportLogic';
import { restoreBundle } from '../services/AtomicStore';
import { generateExport } from '../services/ExportWorker';
import { currentClock } from '../model/SchoolClock';
import { refreshAllForms } from '../services/Forms';
import { scheduleReminders } from '../services/Reminders';
@Entry
@Component
struct Transfer {
  @State busy: boolean = false;
  @State message: string = '';
  @State dark: boolean = false;
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private ink(): string { return this.dark ? '#E8EFF5' : '#243746'; }
  private surface(): string { return this.dark ? '#23313F' : '#FFFFFF'; }
  aboutToAppear(): void { try { const state = loadApp(this.context()); this.dark = state.preferences.theme === 2 || (state.preferences.theme === 0 && (AppStorage.get<boolean>('systemDark') || false)); } catch (_) {} }
  private async exportFile(kind: string): Promise<void> {
    if (this.busy) return; this.busy = true; this.message = '正在准备文件…';
    try {
      const text = backupText(load(this.context()), loadApp(this.context()));
      const bytes = await taskpool.execute(new taskpool.Task(generateExport, text, kind, JSON.stringify(currentClock()))) as ArrayBuffer;
      const paths = await new picker.DocumentViewPicker(this.context()).save({ newFileNames: ['南艺电子课表-' + new Date().toISOString().slice(0, 10) + '.' + kind], fileSuffixChoices: ['.' + kind] });
      if (!paths.length) { this.message = '已取消导出'; return; }
      const file = fileIo.openSync(paths[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { let offset = 0; const view = new Uint8Array(bytes); while (offset < bytes.byteLength) { const count = fileIo.writeSync(file.fd, view.slice(offset).buffer); if (count <= 0) throw new Error('文件未完整写入'); offset += count; } fileIo.fsyncSync(file.fd); } finally { fileIo.closeSync(file); }
      this.message = '已导出到所选位置';
    } catch (e) { this.message = '导出失败：' + (e as Error).message; }
    finally { this.busy = false; }
  }
  private async restore(): Promise<void> {
    if (this.busy) return; this.busy = true;
    try {
      const paths = await new picker.DocumentViewPicker(this.context()).select({ maxSelectNumber: 1 }); if (!paths.length) return;
      const file = fileIo.openSync(paths[0], fileIo.OpenMode.READ_ONLY); let text = '';
      try {
        const size = fileIo.statSync(file.fd).size; if (size < 1 || size > 4 * 1024 * 1024) throw new Error('请选择4MB以内的 JSON 课表备份');
        const bytes = new Uint8Array(size); let offset = 0;
        while (offset < size) { const chunk = new ArrayBuffer(size - offset), count = fileIo.readSync(file.fd, chunk, { offset: offset }); if (count < 1) throw new Error('备份未完整读取'); bytes.set(new Uint8Array(chunk, 0, count), offset); offset += count; }
        text = new util.TextDecoder('utf-8').decodeToString(bytes);
      } finally { fileIo.closeSync(file); }
      const next = parseBackup(text);
      this.getUIContext().showAlertDialog({ title: '确认恢复备份', message: next.snapshot.rules.length + ' 个安排\n开学时间：' + next.snapshot.startDate + '\n' + (next.app ? '同时恢复日程、外观和提醒设置。' : '仅恢复课程，现有日程及设置保留。') + '\n确认前原数据不会改变。', primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '恢复', action: () => this.applyRestore(next) } });
    } catch (e) { this.message = '无法恢复：' + (e as Error).message; }
    finally { this.busy = false; }
  }
  private applyRestore(next: Restored): void {
    try { restoreBundle(this.context(), JSON.stringify(next.snapshot), JSON.stringify(next.app || loadApp(this.context()))); refreshAllForms(this.context()).catch(() => {}); scheduleReminders(this.context()).catch(() => {}); this.message = '备份已恢复，返回课表即可查看'; }
    catch (_) { this.message = '恢复失败，原数据已尝试恢复，请勿清除应用数据'; }
  }
  @Builder private action(title: string, subtitle: string, run: () => void) {
    Column({ space: 10 }) { Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(this.ink()).width('100%'); Text(subtitle).fontSize(13).fontColor(this.ink()).opacity(0.7).width('100%'); }.padding(22).width('100%').backgroundColor(this.surface()).borderRadius(22).enabled(!this.busy).onClick(run)
  }
  build() {
    Column({ space: 16 }) {
      Row() { Text('导出与备份').fontSize(25).fontWeight(FontWeight.Bold).fontColor(this.ink()).layoutWeight(1); Button('返回').backgroundColor(this.surface()).fontColor(this.ink()).onClick(() => this.getUIContext().getRouter().back()); }.width('100%')
      Scroll() {
        Column({ space: 14 }) {
          this.action('课表备份 · JSON', '保留课程详情、日程和设置，不含账号、Cookie 或签名。', () => this.exportFile('json'))
          this.action('导出表格 · XLS', '适合在 Excel 或 WPS 中查看、打印。', () => this.exportFile('xls'))
          this.action('导出日历 · ICS', '把本学期每次上课导入系统日历。', () => this.exportFile('ics'))
          this.action('恢复课表备份', '支持本应用备份，以及兼容的安卓版课程备份；覆盖前会确认。', () => this.restore())
          if (this.busy) { LoadingProgress().width(32).height(32); }
          Text(this.message).fontSize(14).fontColor(this.ink()).width('100%')
        }.width('100%')
      }.layoutWeight(1).width('100%')
    }.padding(20).width('100%').height('100%').backgroundColor(this.dark ? '#121B24' : '#F7F9FB')
  }
}
