'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const ts=require('E:/HarmonyDev/tools/DevEcoStudio/tools/hvigor/hvigor/node_modules/typescript');
const root=path.resolve(__dirname,'..','entry/src/main/ets');
function scenario(kind){
  const cache=new Map(), stats={active:0,max:0,requests:0,market:0,closed:0};
  const release={draft:false,prerelease:false,tag_name:'v1.2.2',body:'说明',html_url:'https://github.com/HerenYU2007/NUA-Schedule-HarmonyOS/releases/tag/v1.2.2'};
  let newerSent=false;
  const stubs={
    '@kit.AbilityKit':{},
    '@kit.ArkTS':{url:{URL},util:{TextDecoder:class{decodeToString(bytes){return Buffer.from(bytes).toString('utf8');}}}},
    '@kit.AppGalleryKit':{updateManager:{UpdateAvailableCode:{LATER_VERSION_EXIST:1,LATER_VERSION_NOT_EXIST:0},async checkAppUpdate(){stats.market++;if(kind==='store')return{updateAvailable:1};throw Error('unpublished');},async showUpdateDialog(){}}},
    '@kit.RemoteCommunicationKit':{rcp:{Request:class{constructor(url){this.url=url;}},createSession(){let closed=false;return{cancel(){closed=true;},close(){if(!closed)stats.closed++;closed=true;},async fetch(request){stats.requests++;stats.active++;stats.max=Math.max(stats.max,stats.active);try{let body={...release};let delay=1;
      if(kind==='newer'&&!newerSent&&!request.url.startsWith('https://api.github.com/')&&!request.url.startsWith('https://raw.githubusercontent.com/')){newerSent=true;body.tag_name='v1.2.3';body.html_url=body.html_url.replace('1.2.2','1.2.3');delay=20;}
      if(kind==='spoof'){body.tag_name='v9.0.0';body.html_url='https://evil.test/download';}
      await new Promise(resolve=>setTimeout(resolve,delay));if(closed)throw Error('cancelled');if(kind==='fail')throw Error('offline');const data=Buffer.from(JSON.stringify(body));request.destination(data.buffer.slice(data.byteOffset,data.byteOffset+data.byteLength));return{statusCode:200,headers:{}};
      }finally{stats.active--;}}};}}}
  };
  function load(name,from=root){if(name.startsWith('@'))return stubs[name];const file=path.resolve(from,name+'.ets');if(cache.has(file))return cache.get(file).exports;const mod={exports:{}};cache.set(file,mod);const output=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText;new Function('require','module','exports',output)(n=>load(n,path.dirname(file)),mod,mod.exports);return mod.exports;}
  return{updates:load('services/Updates'),stats};
}
(async()=>{
  let x=scenario('newer');const results=await Promise.all([x.updates.checkUpdate({},false),x.updates.checkUpdate({},true)]);assert(results.every(r=>r.available&&r.version==='1.2.3'));assert.equal(x.stats.market,1);assert(x.stats.max<=12);assert(x.stats.closed>0);console.log('PASS newer mirror beats old official data; bounded parallelism, cancel and single flight');
  x=scenario('old');assert.equal((await x.updates.checkUpdate({},true)).message,'暂无更新');assert(x.stats.requests>75);console.log('PASS no-update waits for all mirror results');
  x=scenario('fail');assert((await x.updates.checkUpdate({},true)).message.includes('无法检查'));console.log('PASS total network failure is not misreported as no update');
  x=scenario('spoof');assert.equal((await x.updates.checkUpdate({},true)).available,false);console.log('PASS arbitrary download page rejected');
  x=scenario('store');assert.equal((await x.updates.checkUpdate({},true)).store,true);console.log('PASS official Harmony installer channel retained');
})().catch(e=>{console.error(e);process.exitCode=1;});
