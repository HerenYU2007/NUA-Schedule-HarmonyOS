export const PORTAL: string = 'https://i.nua.edu.cn/sopcb/';
export const DIRECT: string = 'https://c.nua.edu.cn/cas/login?service=https%3A%2F%2Fi.nua.edu.cn%2Fsopcb';
export const VPN: string = 'https://v.nua.edu.cn/';
export const HOME: string = 'https://jwnew.nua.edu.cn/jsxsd/framework/xsMain.jsp';
export function school(value: string): boolean {
  return typeof value === 'string' && /^https:\/\/(?:c|i|jwnew|v)\.nua\.edu\.cn(?::443)?(?:\/|$)/i.test(value) && !/[\r\n\\]/.test(value);
}
export function readable(value: string): boolean { return school(value) && !/^https:\/\/c\./i.test(value) && !/\/cas\/(login|logout)(?:[/?#]|$)/i.test(value); }
export function path(value: string): string { return school(value) ? value.replace(/^https:\/\/[^/]+/i, '').split(/[?#]/)[0] || '/' : ''; }
export function vpnPrefix(value: string): string {
  if (!readable(value) || !/^https:\/\/v\.nua\.edu\.cn(?::443)?\//i.test(value)) return '';
  const p = path(value); if (/%|\\|\/\/|\/\.{1,2}(?:\/|$)/.test(p)) return '';
  const route = p.match(/^(\/https\/[A-Za-z0-9_=-]{24,512})\/jsxsd\/[A-Za-z0-9_./-]*$/);
  return route ? route[1] : '';
}
export function academic(value: string): boolean { return readable(value) && (/^https:\/\/jwnew\.nua\.edu\.cn(?::443)?\//i.test(value) || !!vpnPrefix(value)); }
export function homeFor(value: string): string { return vpnPrefix(value) ? 'https://v.nua.edu.cn' + vpnPrefix(value) + '/jsxsd/framework/xsMain.jsp' : academic(value) ? HOME : ''; }
export function personalSettings(value: string): boolean { return academic(value) && /^\/jsxsd\/grsz\//i.test(path(value).slice(vpnPrefix(value).length)); }
export function portalRetry(value: string): string {
  const p = path(value);
  if (/^https:\/\/i\.nua\.edu\.cn(?::443)?\//i.test(value) && /^(\/|\/sopcb\/?)$/.test(p)) return 'https://i.nua.edu.cn' + p;
  return readable(value) && /^https:\/\/v\.nua\.edu\.cn(?::443)?\//i.test(value) && /^\/https\/[A-Za-z0-9_=-]{24,512}\/(?:sopcb\/?)?$/.test(p) ? 'https://v.nua.edu.cn' + p : '';
}
export function downloadReferer(value: string, source: string): string {
  if (!academic(value) || /[?&](ticket|password)=/i.test(value)) return '';
  const prefix = vpnPrefix(value);
  if (prefix) return prefix === vpnPrefix(source) && !personalSettings(source) && /^\/jsxsd\/xskb\//i.test(path(value).slice(prefix.length)) ? homeFor(source) : '';
  return !/\/(cas|sso\.jsp)(?:\/|$)/i.test(path(value)) ? HOME : '';
}
export function address(value: string): string {
  if (value === 'about:blank') return 'about:blank（新窗口占位页）';
  return school(value) ? value.split(/[?#]/)[0].replace(/ST-[^/]+/gi, '*').replace(/[A-Za-z0-9_=-]{24,}/g, '*').replace(/\d{6,}/g, '*').slice(0, 180) : '未进入学校 HTTPS 页面';
}
export function httpsSso(value: string, method: string): string {
  if (method.toUpperCase() !== 'GET' || !/^http:\/\/(?:c|i|jwnew|v)\.nua\.edu\.cn(?::80)?(?:\/|$)/i.test(value) || /[\r\n\\]/.test(value)) return '';
  return value.replace(/^http:/i, 'https:').replace(/^(https:\/\/[^/:]+):80(?=\/|$)/i, '$1');
}
export class Attempts {
  failures: number = 0;
  observed: string = '';
  expected: string = '';
  reset(): void { this.failures = 0; this.observed = ''; this.expected = ''; }
  observe(value: string): void { if (/^https:\/\/v\./i.test(value)) this.observed = 'vpn'; else if (/^https:\/\/jwnew\./i.test(value)) this.observed = 'direct'; }
  fail(): string { if (this.failures >= 2 || ++this.failures >= 2) return ''; this.expected = (this.expected || this.observed) === 'vpn' ? 'direct' : 'vpn'; return this.expected === 'vpn' ? VPN : DIRECT; }
}
