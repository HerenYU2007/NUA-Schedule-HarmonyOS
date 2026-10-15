import { rcp } from '@kit.RemoteCommunicationKit';
import { url } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { downloadReferer } from './SchoolPolicy';
const LIMIT: number = 5 * 1024 * 1024;
export class Download {
  private session: rcp.Session | undefined = undefined;
  cancel(): void { if (this.session) { this.session.close(); this.session = undefined; } }
  async fetch(observedUrl: string, agent: string, source: string): Promise<Uint8Array> {
    this.cancel();
    const session = rcp.createSession(); this.session = session;
    let destination = observedUrl;
    try {
      for (let redirect = 0; redirect < 6; redirect++) {
        // Check every destination before reading Cookie or sending any bytes.
        const referer = downloadReferer(destination, source);
        if (!referer) throw new Error('拒绝非当前教务 HTTPS 通道下载');
        const cookie = webview.WebCookieManager.fetchCookieSync(destination);
        const request = new rcp.Request(destination, 'GET', { 'cookie': cookie, 'user-agent': agent, 'referer': referer });
        request.configuration = { transfer: { autoRedirect: false, timeout: { connectMs: 15000, transferMs: 20000 } } };
        const parts: Uint8Array[] = []; let length = 0;
        request.destination = (data: ArrayBuffer): void => {
          if (length + data.byteLength > LIMIT) { session.cancel(request); throw new Error('下载超过 5MB'); }
          parts.push(new Uint8Array(data)); length += data.byteLength;
        };
        const response = await session.fetch(request);
        if (this.session !== session) throw new Error('下载已取消');
        const setCookie = response.headers['set-cookie'];
        if (typeof setCookie === 'string') await webview.WebCookieManager.configCookie(destination, setCookie);
        else if (Array.isArray(setCookie)) for (const item of setCookie) await webview.WebCookieManager.configCookie(destination, item);
        if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
          const location = response.headers.location;
          if (!location) throw new Error('学校返回无效跳转');
          destination = new url.URL(location, destination).href; continue;
        }
        if (response.statusCode !== 200) throw new Error('学校下载失败');
        const bytes = new Uint8Array(length); let offset = 0;
        for (const part of parts) { bytes.set(part, offset); offset += part.length; }
        return bytes;
      }
      throw new Error('下载跳转次数过多');
    } finally { session.close(); if (this.session === session) this.session = undefined; }
  }
}
