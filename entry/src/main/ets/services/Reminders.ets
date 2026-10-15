import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { load } from './Store';
import { loadApp, readJson, writeJson } from './AppStore';
import { ReminderPlan, reminderPlans } from '../model/AppModel';
interface Registered { id: number; key: string; at: number; title: string; content: string; mode?: number; }
let busy: boolean = false;
let again: boolean = false;
export async function allowNotifications(context: common.UIAbilityContext): Promise<void> {
  if (!await notificationManager.isNotificationEnabled()) await notificationManager.requestEnableNotification(context);
}
export async function scheduleReminders(context: common.Context): Promise<string> {
  if (busy) { again = true; return '提醒正在刷新'; }
  busy = true;
  try {
    const plans = reminderPlans(load(context), loadApp(context), Date.now());
    let old = JSON.parse(readJson(context, 'reminders.json', '[]')) as Registered[];
    if (!old.length && !plans.length) return '当前没有待提醒课程或日程';
    const valid = await reminderAgentManager.getAllValidReminders();
    old = old.filter((r: Registered) => valid.some((v: reminderAgentManager.ReminderInfo) => v.reminderId === r.id));
    writeJson(context, 'reminders.json', JSON.stringify(old));
    for (const r of old.slice()) if (!plans.some((p: ReminderPlan) => p.key === r.key && p.at === r.at && p.title === r.title && p.content === r.content && (p.mode ?? 1) === (r.mode ?? 1))) {
      try { await reminderAgentManager.cancelReminder(r.id); }
      catch (error) { if ((error as BusinessError).code !== 1700003) throw new Error('旧提醒未能取消'); }
      old = old.filter((x: Registered) => x.id !== r.id); writeJson(context, 'reminders.json', JSON.stringify(old));
    }
    if (plans.length && !await notificationManager.isNotificationEnabled()) return '通知未授权，提醒尚未注册';
    for (const p of plans) if (!old.some((r: Registered) => r.key === p.key && r.at === p.at && r.title === p.title && r.content === p.content && (p.mode ?? 1) === (r.mode ?? 1))) {
      const date = new Date(p.at);
      const request: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: { year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate(), hour: date.getHours(), minute: date.getMinutes(), second: 0 },
        title: p.title, content: p.content, ringDuration: p.mode === 2 ? 60 : 0, snoozeTimes: 0,
        wantAgent: { pkgName: 'cn.nua.wenguan.schedule', abilityName: 'EntryAbility' },
        actionButton: [{ title: '关闭', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }]
      };
      const id = await reminderAgentManager.publishReminder(request);
      old.push({ id: id, key: p.key, at: p.at, title: p.title, content: p.content, mode: p.mode ?? 1 });
      try { writeJson(context, 'reminders.json', JSON.stringify(old)); }
      catch (_) { await reminderAgentManager.cancelReminder(id); throw new Error('提醒登记未保存'); }
    }
    return '已注册 ' + old.length + ' 条系统提醒';
  } finally { busy = false; if (again) { again = false; scheduleReminders(context).catch(() => {}); } }
}
