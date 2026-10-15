'use strict';
// Runs the actual pure ArkTS sources through TypeScript in memory: no generated test files or personal data copies.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require('E:/HarmonyDev/tools/DevEcoStudio/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const ets = path.join(root, 'entry/src/main/ets');
const modules = new Map();
function load(relative) {
  const file = path.resolve(ets, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (modules.has(file)) return modules.get(file);
  const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }, fileName: file.replace(/\.ets$/, '.ts')
  }).outputText;
  const module = { exports: {} }; modules.set(file, module.exports);
  new Function('require', 'module', 'exports', output)(
    name => load(path.relative(ets, path.resolve(path.dirname(file), name))), module, module.exports);
  return module.exports;
}
const schedule = load('model/Schedule');
const command = load('model/FormCommand').formCommand;
assert.equal(command('{"command":"tomorrow"}'), 'tomorrow');
assert.equal(command('{"action":"message","params":{"command":"today"}}'), 'today');
assert.equal(command('{"action":"message","params":{"action":"tomorrow"}}'), 'tomorrow');
assert.equal(command('{"action":"refresh"}'), 'refresh');
for (const invalid of ['null', '[]', '"today"', '{}', 'broken', '{"command":"delete"}', '{"action":"message"}', ' '.repeat(2049)]) assert.equal(command(invalid), '');
const parser = load('services/TimetableParser');
const xls = load('services/Xls');
const policy = load('services/SchoolPolicy');
// Synthetic fixture: portable tests must not need anyone's real timetable.
const personal = Array.from({length:32},(_,i)=>({from:1,to:i<10?5:4,day:i%7+1,start:'14:00',end:'15:40',periods:'第5—6节',course:'测试课程'+(i%11),room:'测试教室',teacher:'测试教师',type:'理论'}));
assert.equal(personal.length, 32);
assert.equal(personal.reduce((n, r) => n + r.to - r.from + 1, 0), 138);
assert.equal(new Set(personal.map(r => r.course)).size, 11);
schedule.validSnapshot({ schema: 1, startDate: '2026-09-07', rules: personal, syncedAt: 0 });
for (let day = 7; day <= 13; day++) {
  const start = '2026-09-' + String(day).padStart(2, '0');
  assert.equal(schedule.week(schedule.dayNumber('2026-09-07'), start), 1);
  assert.equal(schedule.week(schedule.dayNumber('2026-09-13'), start), 1);
  assert.equal(schedule.week(schedule.dayNumber('2026-09-14'), start), 2);
}
assert.throws(() => schedule.dayNumber('2026-02-30'));
assert.equal(schedule.dateText(schedule.nowDay(Date.parse('2026-10-08T16:00:00Z'))), '2026-10-09');
assert.equal(schedule.week(schedule.dayNumber('2027-01-04'), '2026-12-30'), 2);
const rule = { from: 1, to: 53, day: 4, start: '14:00', end: '15:40', periods: '第5–6节', course: '测试课', room: '文101', type: '理论', teacher: '测试教师' };
const data = { schema: 1, startDate: '2026-09-07', rules: [rule], syncedAt: 0 };
const time = value => Date.parse('2026-10-08T' + value + '+08:00');
assert.equal(schedule.courseStatus(rule, schedule.dayNumber('2026-10-08'), time('13:59')), '未开始');
assert.equal(schedule.courseStatus(rule, schedule.dayNumber('2026-10-08'), time('14:00')), '正在进行');
assert.equal(schedule.courseStatus(rule, schedule.dayNumber('2026-10-08'), time('15:40')), '已结束');
assert.equal(schedule.cardData(data, -1, time('15:40')).lines.length, 0);
assert(schedule.cardData(data, -1, time('21:59')).title.startsWith('今天'));
assert(schedule.cardData(data, -1, time('22:00')).title.startsWith('明天'));
assert(schedule.cardData(data, -1, Date.parse('2026-10-09T00:00:00+08:00')).title.startsWith('今天'));
assert.notEqual(schedule.formEpoch(time('21:59')), schedule.formEpoch(time('22:00')), 'Manual today selection resets across 22:00');
assert.notEqual(schedule.formEpoch(time('22:00')), schedule.formEpoch(Date.parse('2026-10-09T00:00:00+08:00')), 'Manual tomorrow resets across midnight');
assert(schedule.cardData({ ...data, rules: [] }, -1, time('14:00')).empty.includes('尚未导入'));
const headers = ['课程名称','实际上课时间','实际上课教室','授课教师','理论周次','实践周次'];
const rows = [['测试课','6-8周,周二,第2-4节;9周,周二,第3-4节','文101;校外课堂','测试教师','6-8','9'],['军事技能','6周,周一,第1-4节','操场','测试教师','','']];
const parsed = parser.parseTable({ headers, rows });
assert.equal(parsed.rules.length, 4); assert.equal(parsed.excluded, 1);
assert.equal(parsed.rules[0].start, '08:55'); assert.equal(parsed.rules[3].room, '校外课堂');
assert.equal(parsed.rules[3].type, '实践');
assert.equal(parser.parseTable({ headers, rows: rows.concat(rows) }).rules.length, 4);
assert.deepEqual(parser.parseTable({ headers, rows: [['单双周课','5-10周(单周),星期三,第1-2节','操场','教师']] }).rules.map(r => r.from), [5,7,9]);
assert.throws(() => parser.parseTable({ headers, rows: [['残缺课','6周,周一,第1节;错误时间','文101','教师']] }));
const grid = parser.parseGridCell('文化产业学院\n测试课\n(测试课1班)\n教师\n6-8(周)[01-02-04节]\n文101', 2);
assert.equal(grid.length, 2); assert(grid[0][1].includes('第1-2节')); assert(grid[1][1].includes('第4节'));
assert.throws(() => parser.parseGridCell('测试课\n教师\n6(周)[01-02节]\n文101\n未识别尾部', 2));
for (const target of ['http://jwnew.nua.edu.cn/a','https://jwnew.nua.edu.cn.evil/a','https://evil@jwnew.nua.edu.cn/a','https://jwnew.nua.edu.cn:444/a','https://jwnew.nua.edu.cn\\@evil/a']) assert.equal(policy.school(target), false);
assert(policy.school('https://c.nua.edu.cn/cas/login'));
assert(!policy.readable('https://c.nua.edu.cn/cas/login'));
assert.equal(policy.httpsSso('http://jwnew.nua.edu.cn/sso.jsp?ticket=a%2Bb', 'GET'), 'https://jwnew.nua.edu.cn/sso.jsp?ticket=a%2Bb');
assert.equal(policy.httpsSso('http://jwnew.nua.edu.cn/sso.jsp', 'POST'), '');
assert.equal(policy.address('https://jwnew.nua.edu.cn/sso.jsp?ticket=secret#secret'), 'https://jwnew.nua.edu.cn/sso.jsp');
function u16(n) { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; }
function u32(n) { const b = Buffer.alloc(4); b.writeUInt32LE(n); return b; }
function record(id, bytes) { return Buffer.concat([u16(id),u16(bytes.length),bytes]); }
function text(s) { return Buffer.concat([u16(s.length),Buffer.from([1]),Buffer.from(s, 'utf16le')]); }
function ole(book) {
  assert(book.length <= 4096);
  const bytes = Buffer.alloc(512 + 10 * 512);
  Buffer.from('d0cf11e0a1b11ae1','hex').copy(bytes);
  bytes.writeUInt16LE(3,26); bytes.writeUInt16LE(0xfffe,28); bytes.writeUInt16LE(9,30); bytes.writeUInt16LE(6,32);
  bytes.writeUInt32LE(1,44); bytes.writeUInt32LE(8,48); bytes.writeUInt32LE(4096,56);
  bytes.writeUInt32LE(0xfffffffe,60); bytes.writeUInt32LE(0xfffffffe,68);
  bytes.fill(0xff,76,512); bytes.writeUInt32LE(9,76); book.copy(bytes,512);
  const directory = 512 + 8 * 512;
  for (const [i,name,type,start,len] of [[0,'Root Entry',5,0xfffffffe,0],[1,'Workbook',2,0,4096]]) {
    const p = directory + i * 128; Buffer.from(name+'\0','utf16le').copy(bytes,p);
    bytes.writeUInt16LE((name.length+1)*2,p+64); bytes[p+66]=type;
    bytes.writeUInt32LE(start,p+116); bytes.writeUInt32LE(len,p+120);
  }
  const fat = 512 + 9*512; bytes.fill(0xff,fat,fat+512);
  for(let i=0;i<7;i++) bytes.writeUInt32LE(i+1,fat+i*4);
  bytes.writeUInt32LE(0xfffffffe,fat+7*4); bytes.writeUInt32LE(0xfffffffe,fat+8*4); bytes.writeUInt32LE(0xfffffffd,fat+9*4);
  return bytes;
}
function biffTable(headers, rows, continuation = false) {
  const strings = [...headers,...rows.flat()];
  const content = Buffer.concat([u32(strings.length),u32(strings.length),...strings.map(text)]);
  let sst = record(0xfc,content);
  if (continuation) {
    // Split within the first UTF16 string and insert the CONTINUE encoding byte.
    sst = Buffer.concat([record(0xfc,content.subarray(0,13)),record(0x3c,Buffer.concat([Buffer.from([1]),content.subarray(13)]))]);
  }
  const bof = record(0x809,Buffer.concat([u16(0x600),u16(5),Buffer.alloc(12)]));
  const eof = record(0x0a,Buffer.alloc(0));
  const bound = offset => record(0x85,Buffer.concat([u32(offset),Buffer.from([0,0,1,0,83])]));
  const globalSize = bof.length + bound(0).length + sst.length + eof.length;
  const cells = [headers,...rows].flatMap((row,r) => row.map((_,c) => record(0xfd,Buffer.concat([u16(r),u16(c),u16(0),u32(r===0?c:headers.length+(r-1)*headers.length+c)]))));
  return ole(Buffer.concat([bof,bound(globalSize),sst,eof,bof,...cells,eof]));
}
for (const continueSst of [false,true]) {
  const fixture = biffTable(headers, [rows[0]], continueSst);
  assert.equal(xls.parseXls(fixture).rules.length, 4);
  assert.equal(xls.xlsTables(fixture)[0][0][0], '课程名称');
}
assert.throws(() => xls.parseXls(Buffer.from('<html>not xls</html>')));
assert.throws(() => xls.parseXls(Buffer.alloc(5*1024*1024+1)));
const circular = biffTable(headers, [rows[0]]); circular.writeUInt32LE(0,512+9*512);
assert.throws(() => xls.parseXls(circular));
if (process.argv[2]) {
  const real = xls.parseXls(fs.readFileSync(process.argv[2]));
  assert.equal(new Set(real.rules.map(r=>r.course)).size, 11);
  assert.equal(real.rules.length, 138);
  console.log('User-provided school XLS read-only check passed: 11 courses, 138 meetings; no contents logged/copied.');
}
const store = fs.readFileSync(path.join(ets,'services/Store.ets'),'utf8');
assert(store.includes('writeJson'));
assert(fs.readFileSync(path.join(ets,'services/AtomicStore.ets'),'utf8').includes('fileIo.renameSync(temp, path)'));
assert(!store.includes("putSync('snapshot'"), 'Timetable must not hit Preferences 8KB/string limit');
const card = fs.readFileSync(path.join(ets,'widget/pages/ScheduleCard.ets'),'utf8');
assert(card.includes('@Entry(storage)')); assert(card.includes('justifyContent(FlexAlign.Start)'));
assert(card.includes('TextAlign.Center')); assert(card.includes("command: 'tomorrow'"));
if (fs.existsSync(path.join(ets,'pages/Sync.ets'))) {
  const sync = fs.readFileSync(path.join(ets,'pages/Sync.ets'),'utf8');
  assert(sync.includes('clearAllCookiesSync()')); assert(sync.includes('webview.WebStorage.deleteAllData()'));
  assert(!sync.includes('await webview.WebCookieManager.clearAllCookies()'), 'Initial empty-cookie WebView must not await a callback that may never arrive');
  assert(sync.includes('正在获取课表，请稍后')); assert(sync.includes('handler.handleCancel()'));
  assert(!sync.includes('registerJavaScriptProxy')); assert(!sync.includes('MixedMode.All'));
} else {
  assert(fs.readFileSync(path.join(ets,'model/Variant.ets'),'utf8').includes('PERSONAL: boolean = true'));
  assert(!fs.readFileSync(path.join(root,'entry/src/main/module.json5'),'utf8').includes('ohos.permission.INTERNET'));
}
console.log('Native-source regression passed: personal 32 rules/138 meetings, dates, statuses, 22:00/midnight, empty data, parsing, exclusion, OLE/BIFF/SST CONTINUE, malformed input, school URL guards and card/lifecycle static guards. Real device not exercised.');
