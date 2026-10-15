import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider, formInfo } from '@kit.FormKit';
import { cardData, nowDay, minuteOfDay, courses, Rule, CardData, formEpoch } from '../model/Schedule';
import { load, formChoices, saveChoices, FormChoice } from './Store';
import { cardPayload } from '../model/CardModel';
import { readJson, writeJson } from './AppStore';
export function namedChoice(id: string, name: string, dimension: number): FormChoice { return { id: id, date: formEpoch(), offset: -1, capacity: dimension === 4 ? 5 : 2, kind: name.includes('Week') ? 'week' : 'daily', white: name.startsWith('White'), weekOffset: 0 }; }
export function formDiagnostic(context: common.Context, message: string): void { try { const lines = JSON.parse(readJson(context, 'form-diagnostics.json', '[]')) as string[]; writeJson(context, 'form-diagnostics.json', JSON.stringify(lines.concat([new Date().toISOString() + ' ' + message]).slice(-24))); } catch (_) {} }
export function binding(context: common.Context, choice: FormChoice): formBindingData.FormBindingData {
  try {
    const offset = choice.date === formEpoch() ? choice.offset : -1;
    const snapshot = load(context);
    const data = cardPayload(snapshot, choice.kind || 'daily', choice.white || false, offset, choice.weekOffset || 0, choice.capacity, choice.height ?? (choice.capacity > 2 ? 360 : 180));
    return formBindingData.createFormBindingData(data);
  } catch (_) {
    const error = cardPayload({ schema: 1, startDate: '2026-09-07', rules: [], syncedAt: 0 }, choice.kind || 'daily', choice.white || false, -1, choice.weekOffset || 0, 2, choice.height || 180);
    error.title = '课表暂时无法读取'; error.empty = '点此打开应用查看'; error.next = '';
    return formBindingData.createFormBindingData(error);
  }
}
export async function refreshOne(context: common.Context, choice: FormChoice): Promise<void> {
  await formProvider.updateForm(choice.id, binding(context, choice));
  // System-controlled scheduling, not an unrestricted background timer.
  const minute = minuteOfDay();
  let untilBoundary = minute >= 1320 ? 1440 - minute : 1320 - minute;
  for (const rule of courses(load(context), nowDay())) {
    for (const time of [rule.start, rule.end]) {
      const boundary = Number(time.slice(0, 2)) * 60 + Number(time.slice(3));
      if (boundary > minute) untilBoundary = Math.min(untilBoundary, boundary - minute);
    }
  }
  await formProvider.setFormNextRefreshTime(choice.id, Math.max(5, Math.min(60, untilBoundary)));
}
export async function refreshAllForms(context: common.Context): Promise<void> {
  let live: formInfo.RunningFormInfo[] = [];
  try { live = await formProvider.getPublishedRunningFormInfos(); } catch (_) { /* Preserve registrations if inventory is unavailable. */ }
  // Read after await: don't overwrite a today/tomorrow click made while inventory was pending.
  const choices = formChoices(context);
  for (const item of live) if (item.bundleName === 'cn.nua.wenguan.schedule' && !choices.some((c: FormChoice) => c.id === item.formId)) choices.push(namedChoice(item.formId, item.formName, item.dimension));
  saveChoices(context, choices);
  for (const choice of choices) {
    try { await refreshOne(context, choice); } catch (_) { /* Deleted or rate-limited card: next system update retries. */ }
  }
}
