import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
interface RestoreJournal { schema: number; snapshot: string; app: string; }
function readRaw(context: common.Context, name: string, fallback: string, limit: number = 4 * 1024 * 1024): string {
  const path = context.filesDir + '/' + name; if (!fileIo.accessSync(path)) return fallback;
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  try {
    const size = fileIo.statSync(file.fd).size; if (size < 1 || size > limit) throw new Error('本地文件大小不受支持');
    const bytes = new Uint8Array(size); let offset = 0;
    while (offset < size) { const chunk = new ArrayBuffer(size - offset), count = fileIo.readSync(file.fd, chunk, { offset: offset }); if (count <= 0) throw new Error('本地文件未完整读取'); bytes.set(new Uint8Array(chunk, 0, count), offset); offset += count; }
    return new util.TextDecoder('utf-8').decodeToString(bytes);
  } finally { fileIo.closeSync(file); }
}
function writeRaw(context: common.Context, name: string, text: string): void {
  const path = context.filesDir + '/' + name, temp = path + '.tmp';
  const file = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    const bytes = new util.TextEncoder().encodeInto(text); let offset = 0;
    while (offset < bytes.length) { const count = fileIo.writeSync(file.fd, bytes.slice(offset).buffer); if (count < 1) throw new Error('未完整保存'); offset += count; }
    fileIo.fsyncSync(file.fd);
  } finally { fileIo.closeSync(file); }
  fileIo.renameSync(temp, path);
}
function withLock<T>(context: common.Context, run: () => T): T {
  const file = fileIo.openSync(context.filesDir + '/data.lock', fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
  try { file.tryLock(true); try { return run(); } finally { file.unlock(); } } finally { fileIo.closeSync(file); }
}
function recoverUnlocked(context: common.Context): void {
  const path = context.filesDir + '/restore-journal.json'; if (!fileIo.accessSync(path)) return;
  const journal = JSON.parse(readRaw(context, 'restore-journal.json', '', 16 * 1024 * 1024)) as RestoreJournal;
  if (journal.schema !== 1 || typeof journal.snapshot !== 'string' || typeof journal.app !== 'string') throw new Error('恢复记录损坏，请勿清除应用数据');
  writeRaw(context, 'schedule.json', journal.snapshot); writeRaw(context, 'app-state.json', journal.app); fileIo.unlinkSync(path);
}
export function recoverRestore(context: common.Context): void { withLock<void>(context, () => recoverUnlocked(context)); }
export function readJson(context: common.Context, name: string, fallback: string): string { return withLock<string>(context, () => { recoverUnlocked(context); return readRaw(context, name, fallback); }); }
export function writeJson(context: common.Context, name: string, text: string): void { withLock<void>(context, () => { recoverUnlocked(context); writeRaw(context, name, text); }); }
export function restoreBundle(context: common.Context, snapshot: string, app: string): void {
  withLock<void>(context, () => {
  recoverUnlocked(context);
  const old: RestoreJournal = { schema: 1, snapshot: readRaw(context, 'schedule.json', '{"schema":1,"startDate":"2026-09-07","rules":[],"syncedAt":0}'), app: readRaw(context, 'app-state.json', '{"schema":1,"preferences":{"theme":0,"grid":false,"reminders":false,"minutes":15},"events":[]}') };
  writeRaw(context, 'restore-journal.json', JSON.stringify(old));
  try { writeRaw(context, 'schedule.json', snapshot); writeRaw(context, 'app-state.json', app); fileIo.unlinkSync(context.filesDir + '/restore-journal.json'); }
  catch (_) { recoverUnlocked(context); throw new Error('备份恢复失败，已尝试恢复原数据'); }
  });
}
