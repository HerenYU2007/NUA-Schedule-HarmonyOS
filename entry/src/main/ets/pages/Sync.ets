import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';
import { load, save } from '../services/Store';
import { refreshAllForms } from '../services/Forms';
import { Snapshot, Rule } from '../model/Schedule';
import { Parsed, Table, parseTable } from '../services/TimetableParser';
import { parseXls } from '../services/Xls';
import { Download } from '../services/Download';
import { scheduleReminders } from '../services/Reminders';
import { loadApp } from '../services/AppStore';
import { syncChanges } from '../model/Parity';
import { recordChanges } from '../services/Changes';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PORTAL, HOME, school, readable, academic, address, httpsSso, homeFor, personalSettings, portalRetry, downloadReferer, Attempts } from '../services/SchoolPolicy';
interface SyncParams { manual?: boolean; }
class BrowserWindow {
  id: number;
  controller: webview.WebviewController = new webview.WebviewController();
  handler: ControllerHandler | undefined;
  fitted: boolean = false;
  pendingSecure: string = '';
  constructor(id: number, handler: ControllerHandler | undefined = undefined) { this.id = id; this.handler = handler; }
}
interface NavigationStructure { documents: number; frameErrors: number; tables: number; courseHeader: boolean; timeHeader: boolean; hiddenFrames: number; exportControls: number; }
interface Navigation { kind: string; action?: string; url?: string; academicHome?: boolean; structure?: NavigationStructure; }
interface LoginGeometry { width: number; scale: number; }
@Entry
@Component
struct Sync {
  // Native controllers / popup handlers must never be wrapped by @State's object proxy.
  private windows: BrowserWindow[] = [];
  @State windowIds: number[] = [];
  @State manual: boolean = false;
  @State night: boolean = false;
  @State current: number = 0;
  @State status: string = '请在学校官方页面登录，密码仅输入学校页面';
  @State pageAddress: string = '';
  @State acquiring: boolean = false;
  @State progress: number = 0;
  @State hideNotice: boolean = false;
  @State preview: Parsed | undefined = undefined;
  @State checked: boolean = false;
  @State showDiagnostics: boolean = false;
  @State debug: boolean = false;
  @State schoolDate: string = '2026-09-07';
  @State dateChosen: boolean = false;
  private firstImport: boolean = false;
  @State diagnostics: string[] = [];
  private timer: number = -1;
  private token: number = 0;
  private nextWindow: number = 1;
  private active: boolean = true;
  private stopped: boolean = false;
  private evaluating: boolean = false;
  private downloading: boolean = false;
  private deadline: number = 0;
  private exportSince: number = 0;
  private ssoRetries: number = 0;
  private profileRetries: number = 0;
  private blankCount: number = 0;
  private loginCount: number = 0;
  private recoveries: number = 0;
  private confirmedPortal: string = '';
  private observedPortal: string = '';
  private pendingEntry: string = PORTAL;
  private clearOnAttach: boolean = true;
  private startTimer: number = -1;
  private lastStructure: number = 0;
  private attempts: Attempts = new Attempts();
  private upgrades: Set<string> = new Set<string>();
  private navigation: string = '';
  private extraction: string = '';
  private loginFit: string = '';
  private webWidth: number = 360;
  private download: Download = new Download();
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private browser(): BrowserWindow | undefined { return this.windows.find((w: BrowserWindow) => w.id === this.current); }
  private replaceWindows(values: BrowserWindow[]): void { this.windows = values; this.windowIds = values.map((w: BrowserWindow) => w.id); }
  private windowById(id: number): BrowserWindow { const value = this.windows.find((w: BrowserWindow) => w.id === id); if (!value) throw new Error('窗口已关闭'); return value; }
  private event(message: string, path: string = ''): void {
    const safe = message + (path ? ' · ' + address(path) : '');
    this.diagnostics = this.diagnostics.concat([safe]).slice(-80);
    hilog.warn(0xFF11, 'NuaSync', '%{public}s', safe);
  }
  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as SyncParams;
    this.manual = params?.manual === true;
    try { const local = load(this.context()); this.schoolDate = local.startDate; this.firstImport = !local.rules.length; this.dateChosen = !this.firstImport; const prefs = loadApp(this.context()).preferences; this.debug = prefs.debug || false; const theme = prefs.theme; this.night = theme === 2 || (theme === 0 && this.context().config.colorMode === 0); } catch (_) {}
    webview.WebviewController.setWebDebuggingAccess(false);
    try {
      const decoder = new util.TextDecoder('utf-8');
      this.navigation = decoder.decodeToString(this.context().resourceManager.getRawFileContentSync('schedule-navigation.js'));
      this.extraction = decoder.decodeToString(this.context().resourceManager.getRawFileContentSync('schedule-extract.js'));
      this.loginFit = decoder.decodeToString(this.context().resourceManager.getRawFileContentSync('login-fit.js'));
    } catch (_) { this.stopped = true; this.status = '同步组件未能加载，请重新安装；原课表未改变'; return; }
    if (this.manual) { this.stopped = true; setTimeout(() => this.importFile(), 300); }
    else this.replaceWindows([new BrowserWindow(0)]);
  }
  onPageShow(): void {
    this.active = true;
    if (this.timer < 0) this.timer = setInterval(() => { this.poll(); }, 1500);
  }
  onPageHide(): void {
    this.active = false; this.token++; this.evaluating = false; this.downloading = false; this.acquiring = false;
    if (this.timer >= 0) clearInterval(this.timer); this.timer = -1;
    if (this.startTimer >= 0) clearTimeout(this.startTimer); this.startTimer = -1;
    this.download.cancel();
    this.windows.forEach((w: BrowserWindow) => { try { w.controller.stop(); } catch (_) {} });
  }
  aboutToDisappear(): void {
    this.onPageHide();
    if (!this.manual) { try { webview.WebCookieManager.clearAllCookiesSync(); webview.WebStorage.deleteAllData(); } catch (_) {} }
  }
  private fail(message: string): void {
    if (this.stopped) return;
    const entry = this.attempts.fail();
    this.event('通道失败 ' + this.attempts.failures + '/2：' + message);
    if (entry) { this.switchRoute(entry); return; }
    this.stopped = true; this.acquiring = false; this.status = message + '；原课表未改变';
    this.event(message); this.download.cancel(); this.downloading = false;
    this.getUIContext().showAlertDialog({ title: '获取失败，请稍后重试', message: '两个通道均未完成获取，原课表未改变。也可以手动导入学校导出的 XLS。', primaryButton: { value: '关闭', action: () => {} }, secondaryButton: { value: '导入 XLS', action: () => this.importFile() } });
  }
  private switchRoute(entry: string): void {
    this.token++; this.download.cancel(); this.downloading = false; this.evaluating = false;
    this.windows.forEach((w: BrowserWindow) => { try { w.controller.stop(); } catch (_) {} });
    this.pendingEntry = entry; this.clearOnAttach = false; this.stopped = false;
    this.deadline = 0; this.exportSince = 0; this.blankCount = 0; this.loginCount = 0; this.recoveries = 0; this.confirmedPortal = ''; this.observedPortal = ''; this.upgrades.clear(); this.ssoRetries = 0;
    this.current = this.nextWindow++; this.replaceWindows([new BrowserWindow(this.current)]);
    this.event('启动备用通道（保留本轮登录 Cookie）', entry);
  }
  private freshLogin(window: BrowserWindow): void {
    const token = ++this.token;
    this.stopped = true; this.acquiring = false; this.downloading = false; this.evaluating = false;
    this.hideNotice = false; this.preview = undefined; this.exportSince = 0; this.deadline = 0;
    this.upgrades.clear(); this.ssoRetries = 0; this.profileRetries = 0; this.download.cancel();
    this.status = '正在清空原账号 Cookie，请重新登录';
    try {
      window.controller.stop();
      this.event('开始清理临时学校会话');
      webview.WebStorage.deleteAllData();
      // No asynchronous clear callback may outlive this page or erase a later login.
      // An empty-cookie ArkWeb instance on this device left the Promise pending indefinitely.
      webview.WebCookieManager.clearAllCookiesSync();
      if (webview.WebCookieManager.existCookie()) throw new Error('登录会话未清理');
      this.event('旧登录已清空');
      this.status = '正在连接学校入口，请稍后';
      this.clearOnAttach = false;
      // Allow the initial about:blank lifecycle to finish before loading the real URL.
      this.startTimer = setTimeout(() => {
        this.startTimer = -1;
        if (!this.active || token !== this.token || !this.windows.some((w: BrowserWindow) => w.id === window.id)) return;
        this.stopped = false; this.event('已清空登录，连接学校入口', PORTAL);
        try { window.controller.loadUrl(PORTAL); } catch (_) { this.fail('学校入口未能加载'); }
      }, 100);
    } catch (_) { if (token === this.token) { this.stopped = true; this.status = '旧登录未能清空，请重新获取；未继续使用旧会话'; } }
  }
  private restart(): void {
    this.token++; this.download.cancel(); this.current = this.nextWindow++;
    this.attempts.reset(); this.manual = false; this.stopped = false; this.clearOnAttach = true; this.pendingEntry = PORTAL;
    this.confirmedPortal = ''; this.observedPortal = ''; this.recoveries = 0; this.blankCount = 0; this.loginCount = 0;
    this.replaceWindows([new BrowserWindow(this.current)]);
  }
  private logout(): void {
    this.token++; this.stopped = true; this.acquiring = false; this.download.cancel(); this.downloading = false; this.preview = undefined;
    this.windows.forEach((w: BrowserWindow) => { try { w.controller.stop(); w.controller.loadUrl('about:blank'); } catch (_) {} });
    try { webview.WebCookieManager.clearAllCookiesSync(); webview.WebStorage.deleteAllData(); this.status = '已退出学校登录，原课表保留'; }
    catch (_) { this.status = '退出未能完成，请关闭同步页后重试'; }
  }
  private textColor(): string { return this.night ? '#E8EFF5' : '#243746'; }
  private muted(): string { return this.night ? '#BAC8D4' : '#5B6B78'; }
  private control(): string { return this.night ? '#23313F' : '#EDF2F5'; }
  private intercept(window: BrowserWindow, request: WebResourceRequest): boolean {
    if (!this.active || this.stopped || !this.windows.some((w: BrowserWindow) => w.id === window.id)) return true;
    const target = request.getRequestUrl();
    if (target === 'about:blank') return false;
    if (school(target)) return false;
    const secure = httpsSso(target, request.getRequestMethod());
    if (secure && this.upgrades.has(secure)) {
      if (++this.ssoRetries > 8) this.fail('学校HTTPS入口重复跳转超限');
      return true;
    }
    if (secure && this.upgrades.size < 8) {
      this.upgrades.add(secure); this.event('学校 SSO 明文地址改用 HTTPS（不发送明文）');
      setTimeout(() => { if (this.active && !this.stopped) window.controller.loadUrl(secure); }, 0);
      return true;
    }
    if (request.isMainFrame()) this.fail('跳转被拦截，请查看同步诊断');
    return true;
  }
  private newWindow(event: OnWindowNewEvent): void {
    this.event('收到学校新窗口请求', httpsSso(event.targetUrl || '', 'GET') || event.targetUrl || 'about:blank');
    if (this.windows.length >= 6 || this.stopped || !this.active
      || (event.targetUrl && event.targetUrl !== 'about:blank' && !school(event.targetUrl) && !httpsSso(event.targetUrl, 'GET'))) {
      this.event('新窗口请求被安全策略拒绝'); event.handler.setWebController(null); return;
    }
    const next = new BrowserWindow(this.nextWindow++, event.handler);
    next.pendingSecure = httpsSso(event.targetUrl || '', 'GET');
    this.current = next.id;
    this.replaceWindows(this.windows.concat([next]));
  }
  private pageBegin(window: BrowserWindow, target: string): void {
    if (!this.active || this.stopped || !this.windows.some((w: BrowserWindow) => w.id === window.id)) return;
    if (!school(target)) { this.acquiring = false; return; }
    this.current = window.id; this.token++; this.evaluating = false;
    this.attempts.observe(target);
    const portal = portalRetry(target); if (portal) this.observedPortal = portal;
    // Merely loading the portal before its initial CAS redirect is not proof of login.
    if (academic(target) && this.observedPortal) this.confirmedPortal = this.observedPortal;
    this.pageAddress = address(target); this.event('加载学校页面', target);
    if (!readable(target)) {
      this.acquiring = false; this.status = '请完成学校官方认证，登录后自动获取课表'; this.deadline = 0;
      if (this.confirmedPortal && this.recoveries++ < 1) {
        const token = this.token;
        this.event('登录后回到认证页，保留Cookie重载已确认入口一次');
        setTimeout(() => { if (token === this.token && this.active && !this.stopped) window.controller.loadUrl(this.confirmedPortal); }, 900);
      }
    }
  }
  private async poll(): Promise<void> {
    const browser = this.browser();
    if (!this.active || this.stopped || this.preview || this.evaluating || this.downloading || !browser) return;
    let target: string;
    try { target = browser.controller.getUrl(); } catch (_) { return; }
    if (!readable(target)) { this.acquiring = false; this.deadline = 0; return; }
    if (!this.deadline) this.deadline = Date.now() + 180000;
    if (Date.now() > this.deadline) { this.fail('自动获取超时，请重试'); return; }
    if (personalSettings(target)) {
      if (this.profileRetries++ < 1) browser.controller.loadUrl(homeFor(target));
      else this.fail('学校仍显示个人信息页，已停止自动跳转');
      return;
    }
    this.evaluating = true; const token = this.token;
    try {
      const raw = await browser.controller.runJavaScript(this.navigation);
      if (!this.active || this.stopped || token !== this.token) return;
      const action = JSON.parse(this.decode(raw)) as Navigation;
      if (action.kind === 'acted' || action.kind === 'open') this.event(action.action || '执行菜单操作', target);
      if (action.structure && Date.now() - this.lastStructure > 8000) {
        this.lastStructure = Date.now(); const s = action.structure;
        this.event('取课阶段：' + action.kind + '，页面=' + s.documents + '，框架错误=' + s.frameErrors + '，表格=' + s.tables + '，隐藏框架=' + s.hiddenFrames + '，导出=' + s.exportControls, target);
      }
      if ((action.kind === 'acted' || action.kind === 'ready' || action.academicHome) && this.observedPortal) this.confirmedPortal = this.observedPortal;
      this.acquiring = action.kind !== 'login' && action.kind !== 'sso_required';
      this.status = '自动获取课表 · ' + (action.action ?? '等待学校数据');
      if (action.kind === 'sso_required') {
        if (++this.loginCount >= 6) this.recoverOrFail(browser, '教务会话等待超时');
      } else if (action.kind === 'blank') {
        if (++this.blankCount >= 6) this.recoverOrFail(browser, '学校页面持续空白');
      } else if (action.kind === 'open' && action.url && school(action.url) && academic(action.url)) browser.controller.loadUrl(action.url);
      else if (action.kind === 'export' || action.kind === 'export_wait') {
        if (!this.exportSince) this.exportSince = Date.now();
        if (Date.now() - this.exportSince > 12000) {
          await browser.controller.runJavaScript('window.__nuaAllowPageFallback = true;');
          this.exportSince = 0; this.event('导出未响应，尝试当前课表页面读取');
        }
      } else if (action.kind === 'ready' || action.kind === 'wait') {
        const json = this.decode(await browser.controller.runJavaScript(this.extraction));
        if (json && json !== 'null' && json !== '""' && this.active && token === this.token && !this.stopped) {
          this.showPreview(parseTable(JSON.parse(json) as Table));
        }
      }
      if (action.kind !== 'blank') this.blankCount = 0;
      if (action.kind !== 'sso_required') this.loginCount = 0;
    } catch (_) { if (token === this.token) { this.acquiring = false; this.event('页面格式未识别（不记录正文）'); } }
    finally { if (token === this.token) this.evaluating = false; }
  }
  private recoverOrFail(browser: BrowserWindow, reason: string): void {
    if (this.confirmedPortal && this.recoveries++ < 1) {
      this.blankCount = 0; this.loginCount = 0; this.exportSince = 0;
      this.event(reason + '，保留Cookie重载已确认入口一次');
      browser.controller.loadUrl(this.confirmedPortal);
    } else this.fail(reason);
  }
  private decode(raw: string): string {
    if (!raw) return '';
    // ArkWeb versions differ: a JS string can be returned raw or JSON encoded.
    if (raw.charAt(0) === '"') return JSON.parse(raw) as string;
    return raw;
  }
  private async fitLogin(window: BrowserWindow, target: string): Promise<void> {
    if (!this.active || !school(target) || readable(target) || window.fitted) return;
    try {
      const raw = this.decode(await window.controller.runJavaScript(this.loginFit)); if (!raw) return;
      const shape = JSON.parse(raw) as LoginGeometry;
      if (!Number.isFinite(shape.width) || !Number.isFinite(shape.scale) || shape.width < 100 || shape.scale <= 0 || window.fitted) return;
      const factor = Math.max(0.5, Math.min(4, this.webWidth * 0.92 / shape.width / shape.scale));
      window.fitted = true;
      if (factor > 1.05) window.controller.zoom(factor);
      setTimeout(() => { if (this.active) window.controller.runJavaScript("(function(){var p=window.__nuaLoginPanel;if(!p)return;var r=p.getBoundingClientRect(),v=window.visualViewport;window.scrollTo(Math.max(0,window.scrollX+r.left-(v?v.width:innerWidth)/2+r.width/2),Math.max(0,window.scrollY+r.top-20));})()").catch(() => {}); }, 150);
      this.event('已按屏幕宽度放大桌面登录区域');
    } catch (_) { /* Keep ordinary pinch zoom available if this school layout has changed. */ }
  }
  private showPreview(parsed: Parsed): void {
    this.preview = parsed; this.checked = parsed.warnings.length === 0;
    this.acquiring = false; this.downloading = false; this.status = '已识别课表，请核对后确认导入';
    this.event('识别完成：' + parsed.rules.length + ' 次上课');
    if (this.firstImport && !this.dateChosen) setTimeout(() => this.pickSchoolDate(), 200);
  }
  private pickSchoolDate(): void {
    const date = this.schoolDate;
    this.getUIContext().showDatePickerDialog({ start: new Date(2020, 0, 1), end: new Date(2040, 11, 31), selected: new Date(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8))), onAccept: (v: DatePickerResult) => {
      this.schoolDate = String(v.year) + '-' + String((v.month ?? 0) + 1).padStart(2, '0') + '-' + String(v.day).padStart(2, '0'); this.dateChosen = true;
    } });
  }
  private async downloadXls(event: OnDownloadStartEvent): Promise<void> {
    if (!this.active || this.stopped || this.preview || this.downloading) return;
    let source = '';
    for (const window of this.windows) { try { const candidate = window.controller.getUrl(); if (downloadReferer(event.url, candidate)) { source = candidate; break; } } catch (_) {} }
    if (!source || event.contentLength > 5 * 1024 * 1024) { this.event('拒绝非当前教务 HTTPS 或过大下载'); return; }
    this.downloading = true; this.acquiring = true; const token = this.token;
    this.status = '正在获取课表，请稍后';
    try {
      const bytes = await this.download.fetch(event.url, event.userAgent, source);
      if (this.active && token === this.token && !this.stopped) this.showPreview(parseXls(bytes));
    } catch (_) {
      if (token === this.token && this.active && !this.stopped) {
        this.event('XLS 下载或解析失败（不记录地址参数、Cookie 或正文）');
        this.acquiring = false;
        const browser = this.browser();
        if (browser) await browser.controller.runJavaScript('window.__nuaAllowPageFallback = true;').catch(() => {});
      }
    } finally { if (token === this.token) this.downloading = false; }
  }
  private async importFile(): Promise<void> {
    this.token++; this.download.cancel(); this.evaluating = false; this.downloading = false; this.stopped = true; this.acquiring = false;
    this.windows.forEach((w: BrowserWindow) => { try { w.controller.stop(); } catch (_) {} });
    try {
      const files = await new picker.DocumentViewPicker(this.context()).select({ maxSelectNumber: 1 });
      if (!files.length) return;
      const file = fileIo.openSync(files[0], fileIo.OpenMode.READ_ONLY);
      try {
        const size = fileIo.statSync(file.fd).size;
        if (size > 5 * 1024 * 1024 || size < 8) throw new Error('文件大小不受支持');
        const bytes = new ArrayBuffer(size); let offset = 0;
        while (offset < size) {
          const chunk = new ArrayBuffer(size - offset);
          const read = fileIo.readSync(file.fd, chunk, { offset: offset, length: size - offset });
          if (read <= 0) throw new Error('文件未完整读取');
          new Uint8Array(bytes).set(new Uint8Array(chunk, 0, read), offset); offset += read;
        }
        this.showPreview(parseXls(new Uint8Array(bytes)));
      } finally { fileIo.closeSync(file); }
    } catch (_) { this.acquiring = false; this.status = '所选 XLS 未能读取或格式不支持，原课表未改变'; }
  }
  private confirmImport(): void {
    const parsed = this.preview;
    if (!parsed || !this.checked || !this.dateChosen) return;
    try {
      const current = load(this.context());
      const snapshot: Snapshot = { schema: 1, startDate: this.schoolDate, rules: parsed.rules, syncedAt: Date.now() };
      const changes = syncChanges(current, snapshot);
      save(this.context(), snapshot); try { recordChanges(this.context(), changes); } catch (_) { this.event('课程已保存，变更记录未保存'); }
      refreshAllForms(this.context()).catch(() => {}); scheduleReminders(this.context()).catch(() => {});
      this.getUIContext().showAlertDialog({ title: '课表已导入', message: '课程、桌面卡片和提醒已开始更新。' + (changes.length ? '\n检测到课表变化，返回应用可查看。' : ''), autoCancel: false, confirm: { value: '查看课表', action: () => this.getUIContext().getRouter().back() } });
    } catch (_) { this.status = '课表未能保存，请重试，未主动清除原课表'; }
  }
  @Builder private browserView(window: BrowserWindow) {
            // A popup receives its initial navigation from setWebController. Loading about:blank
            // here overwrites that navigation and leaves a valid SSO window permanently empty.
            Web({ src: window.handler ? '' : 'about:blank', controller: window.controller })
              .javaScriptAccess(true).domStorageAccess(true).databaseAccess(true).fileAccess(false)
              .metaViewport(true).textZoomRatio(110)
              .mixedMode(MixedMode.None).multiWindowAccess(true).allowWindowOpenMethod(true)
              .visibility(window.id === this.current ? Visibility.Visible : Visibility.Hidden)
              .onControllerAttached(() => {
                this.event('网页控制器已就绪');
                const chrome = window.controller.getUserAgent().match(/Chrome\/([0-9.]+)/);
                if (chrome) window.controller.setCustomUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/' + chrome[1] + ' Safari/537.36');
                if (window.handler) {
                  window.handler.setWebController(window.controller); this.event('已绑定学校新窗口');
                  if (window.pendingSecure) {
                    const secure = window.pendingSecure; window.pendingSecure = '';
                    setTimeout(() => { if (this.active && !this.stopped && this.windows.includes(window)) { this.event('学校新窗口入口改用HTTPS（不发送明文）', secure); window.controller.loadUrl(secure); } }, 100);
                  }
                }
                else if (this.clearOnAttach) this.freshLogin(window);
                else window.controller.loadUrl(this.pendingEntry);
              })
              .onLoadIntercept((event: OnLoadInterceptEvent): boolean => this.intercept(window, event.data))
              .onPageBegin((event: OnPageBeginEvent) => this.pageBegin(window, event.url))
              .onPageEnd((event: OnPageEndEvent) => { this.fitLogin(window, event.url); setTimeout(() => this.fitLogin(window, event.url), 600); })
              .onProgressChange((event: OnProgressChangeEvent) => { if (window.id === this.current) this.progress = event.newProgress; })
              .onWindowNew((event: OnWindowNewEvent) => this.newWindow(event))
              .onDownloadStart((event: OnDownloadStartEvent) => this.downloadXls(event))
              .onErrorReceive((event: OnErrorReceiveEvent) => { if (this.windows.some((w: BrowserWindow) => w.id === window.id) && event.request.isMainFrame()) this.fail('学校页面连接失败'); })
              .onSslErrorEventReceive((event: OnSslErrorEventReceiveEvent) => { event.handler.handleCancel(); if (this.windows.some((w: BrowserWindow) => w.id === window.id)) this.fail('学校证书校验失败，未绕过'); })
              .width('100%').height('100%').onAreaChange((_old: Area, area: Area) => { if (window.id === this.current) this.webWidth = Number(area.width); })
  }
  build() {
    Column({ space: 8 }) {
      Row() {
        Text('关闭').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').padding(9).onClick(() => this.getUIContext().getRouter().back())
        Column({ space: 3 }) { Text(this.manual ? '导入 XLS 课表' : '登录教务并同步').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#FFFFFF'); Text('密码仅输入学校官方页面').fontSize(11).fontColor('#CFE4F2'); }.layoutWeight(1)
        if (this.debug) { Text('退出登录').fontSize(13).fontColor('#CFE4F2').padding(9).onClick(() => this.logout()) }
      }.width('100%').padding({ top: 9, bottom: 9, left: 12, right: 8 }).backgroundColor(this.night ? '#173B59' : '#1F4E78')
      Progress({ value: this.progress, total: 100, type: ProgressType.Linear }).height(3).width('100%').color(this.night ? '#9ED6FF' : '#1F4E78')
      Text(this.status).fontSize(12).fontColor(this.muted()).width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 }).backgroundColor(this.night ? '#1C2833' : '#F3F6F8')
      if (this.debug) { Button('学校入口 · 清空登录并重连', { type: ButtonType.Normal }).fontSize(13).fontColor(this.textColor()).backgroundColor(this.control()).borderRadius(14).height(44).width('94%').onClick(() => this.restart())
      Text(this.pageAddress).fontSize(11).fontColor(this.muted()).maxLines(1).width('100%').padding({ left: 14, right: 14 }) }
      if (this.preview) {
        Scroll() {
          Column({ space: 14 }) {
            Text('确认课表 · 不会立即覆盖').fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.textColor())
            Text(this.preview.rules.length + ' 次上课 · 已排除军事技能').fontSize(15).fontColor(this.textColor())
            Text(Array.from(new Set<string>(this.preview.rules.map((r: Rule) => r.course))).join('、')).fontSize(15).fontColor(this.textColor())
            Text(this.preview.warnings.join('\n')).fontSize(13).fontColor('#A54D2B')
            Button('开学时间：' + this.schoolDate + (this.dateChosen ? '' : ' · 请选择')).fontColor(this.textColor()).backgroundColor(this.control()).onClick(() => this.pickSchoolDate())
            Text('选择日期所在的整周作为第1周。请核对学期、周次及全部课程。').fontSize(13).fontColor(this.muted())
            Row() { Checkbox().select(this.checked).onChange((v: boolean) => { this.checked = v; }); Text('已核对以上内容').fontSize(14) }
            Button('确认导入').enabled(this.checked && this.dateChosen).onClick(() => this.confirmImport())
            Button('取消（原课表不变）').onClick(() => { this.preview = undefined; this.stopped = true; this.status = '已取消导入，原课表未改变'; })
          }.padding(16).width('100%')
        }.layoutWeight(1)
      }
        Stack() {
          ForEach(this.windowIds, (id: number) => {
            this.browserView(this.windowById(id))
          }, (id: number) => String(id))
          if (this.acquiring && !this.hideNotice) {
            Column({ space: 14 }) {
              LoadingProgress().width(36).height(36).color('#214E72')
              Text('正在获取课表，请稍后').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.textColor())
              Button('隐藏提示（继续获取）').fontSize(12).onClick(() => { this.hideNotice = true; })
            }.padding(24).backgroundColor(this.night ? '#F41C2833' : '#F4FFFFFF').borderRadius(20)
          }
        }.width('100%').layoutWeight(this.preview ? 0 : 1).height(this.preview ? 0 : undefined)
          .visibility(this.preview ? Visibility.Hidden : Visibility.Visible)
      Button('重新获取课表（清空登录）', { type: ButtonType.Normal }).fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.night ? '#102A3E' : '#FFFFFF').backgroundColor(this.night ? '#9ED6FF' : '#1F4E78').borderRadius(14).height(48).width('94%').onClick(() => this.restart())
      if (this.debug) { Row({ space: 8 }) {
        Button('导入已下载的 XLS（备用）', { type: ButtonType.Normal }).fontSize(13).fontColor(this.textColor()).backgroundColor(this.control()).borderRadius(14).height(44).layoutWeight(1).onClick(() => this.importFile())
        Button('同步诊断', { type: ButtonType.Normal }).fontSize(13).fontColor(this.textColor()).backgroundColor(this.control()).borderRadius(14).height(44).onClick(() => { this.showDiagnostics = !this.showDiagnostics; })
      }.width('94%')
      }
      if (this.debug && this.showDiagnostics) {
        Scroll() { Text(this.diagnostics.join('\n') + '\n仅含状态和脱敏路径，不含账号密码、Cookie、登录票据或页面正文。').fontSize(11).fontColor(this.muted()).copyOption(CopyOptions.LocalDevice).width('100%') }.height(140).width('94%')
      }
    }.padding({ bottom: 12 }).height('100%').width('100%').backgroundColor(this.night ? '#121B24' : '#F7F9FB')
  }
}
