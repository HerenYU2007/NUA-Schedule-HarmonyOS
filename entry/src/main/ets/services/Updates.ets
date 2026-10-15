import { common } from '@kit.AbilityKit';
import { updateManager } from '@kit.AppGalleryKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { util, url } from '@kit.ArkTS';
import { MIRRORS, HARMONY_METADATA } from '../model/UpdateRoutes';
export interface UpdateResult { available: boolean; version: string; notes: string; page: string; store: boolean; message: string; }
interface Release { draft: boolean; prerelease: boolean; tag_name: string; body: string; html_url: string; }
export const RELEASES: string = 'https://github.com/HerenYU2007/NUA-Schedule-HarmonyOS/releases';
const API: string = 'https://api.github.com/repos/HerenYU2007/NUA-Schedule-HarmonyOS/releases/latest';
const CURRENT: string = '1.2.4';
let last: number = 0;
let flight: Promise<UpdateResult> | undefined = undefined;
let cached: UpdateResult | undefined = undefined;
export function versionCode(value: string): number {
  if (!/^v?\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(value)) return 0;
  const p = value.replace(/^v/, '').split('.').map((n: string) => Number(n));
  return p[0] * 1000000 + p[1] * 1000 + p[2];
}
export function releaseResult(release: Release): UpdateResult {
  if (!release || release.draft !== false || release.prerelease !== false || typeof release.tag_name !== 'string' || !versionCode(release.tag_name) || release.html_url !== RELEASES + '/tag/' + release.tag_name) throw new Error('更新信息无效');
  return { available: versionCode(release.tag_name) > versionCode(CURRENT), version: release.tag_name.replace(/^v/, ''), notes: typeof release.body === 'string' ? release.body.slice(0, 4000) : '软件更新', page: release.html_url, store: false, message: '暂无更新' };
}
export async function checkUpdate(context: common.UIAbilityContext, manual: boolean): Promise<UpdateResult> {
  if (flight) return flight;
  if (!manual && cached && Date.now() - last < 60000) return cached;
  last = Date.now();
  flight = new UpdateRace(context).run();
  try { cached = await flight; return cached; } finally { flight = undefined; }
}
class UpdateRace {
  private context: common.UIAbilityContext;
  private sessions: rcp.Session[] = [];
  private stopped: boolean = false;
  private valid: number = 0;
  private sources: string[] = [API, HARMONY_METADATA].concat(MIRRORS.map((s: string) => s + HARMONY_METADATA));
  private next: number = 0;
  private remaining: number = 13;
  private resolve: (value: UpdateResult) => void = () => {};
  private timer: number = -1;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  run(): Promise<UpdateResult> {
    return new Promise<UpdateResult>((resolve) => {
      this.resolve = resolve;
      this.timer = setTimeout(() => this.finish(this.none()), 45000);
      this.market();
      for (let i = 0; i < 12; i++) this.worker();
    });
  }
  private none(): UpdateResult { return { available: false, version: '', notes: '', page: RELEASES, store: false, message: this.valid ? '暂无更新' : '暂时无法检查更新，请稍后重试' }; }
  private finish(result: UpdateResult): void {
    if (this.stopped) return; this.stopped = true; if (this.timer >= 0) clearTimeout(this.timer);
    for (const s of this.sessions) { try { s.close(); } catch (_) {} } this.sessions = []; this.resolve(result);
  }
  private ended(): void { if (--this.remaining === 0) this.finish(this.none()); }
  private async market(): Promise<void> {
    try {
      const found = await updateManager.checkAppUpdate(this.context);
      if (found.updateAvailable === updateManager.UpdateAvailableCode.LATER_VERSION_EXIST) this.finish({ available: true, version: '', notes: '华为应用市场已有新版本，可查看更新内容并确认安装。', page: '', store: true, message: '' });
      else if (found.updateAvailable === updateManager.UpdateAvailableCode.LATER_VERSION_NOT_EXIST) this.valid++;
    } catch (_) { /* Unpublished/debug apps may not be in AppGallery. */ }
    finally { this.ended(); }
  }
  private async worker(): Promise<void> {
    try {
      while (!this.stopped && this.next < this.sources.length) {
        const source = this.sources[this.next++]; const session = rcp.createSession(); this.sessions.push(session);
        try {
          const request = new rcp.Request(source, 'GET', { 'accept': 'application/json', 'user-agent': 'NUA-Schedule-HarmonyOS' });
          request.configuration = { transfer: { autoRedirect: false, timeout: { connectMs: 4000, transferMs: 6000 } } };
          const parts: Uint8Array[] = []; let size = 0;
          request.destination = (data: ArrayBuffer): void => { size += data.byteLength; if (size > 256 * 1024) { session.cancel(request); throw new Error('更新信息过大'); } parts.push(new Uint8Array(data)); };
          const response = await session.fetch(request);
          if (this.stopped) return;
          if (response.statusCode !== 200) continue;
          const bytes = new Uint8Array(size); let at = 0; for (const p of parts) { bytes.set(p, at); at += p.length; }
          const result = releaseResult(JSON.parse(new util.TextDecoder('utf-8').decodeToString(bytes)) as Release); this.valid++;
          // An old valid mirror cannot end the race and hide a newer result.
          if (result.available) { this.finish(result); return; }
        } catch (_) { /* One failed mirror does not decide the whole check. */ }
        finally { try { session.close(); } catch (_) {} this.sessions = this.sessions.filter((s: rcp.Session) => s !== session); }
      }
    } finally { this.ended(); }
  }
}
export async function openUpdate(context: common.UIAbilityContext, update: UpdateResult): Promise<void> {
  if (update.store) { await updateManager.showUpdateDialog(context); return; }
  if (!update.page.startsWith(RELEASES + '/tag/') || new url.URL(update.page).hostname !== 'github.com') throw new Error('更新页面不可信');
  // Mirrors provide notices only. Harmony packages are installed through official distribution.
  await context.openLink(update.page);
}
