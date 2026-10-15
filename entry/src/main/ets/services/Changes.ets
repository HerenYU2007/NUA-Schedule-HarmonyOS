import { common, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { ChangeLine } from '../model/Parity';
import { readJson, writeJson } from './AppStore';
export function pendingChanges(context: common.Context): ChangeLine[] { return JSON.parse(readJson(context, 'schedule-changes.json', '[]')) as ChangeLine[]; }
export function acknowledgeChanges(context: common.Context): void { writeJson(context, 'schedule-changes.json', '[]'); }
export function recordChanges(context: common.Context, changes: ChangeLine[]): void {
  if (!changes.length) return;
  writeJson(context, 'schedule-changes.json', JSON.stringify(changes));
  publish().catch(() => {});
}
async function publish(): Promise<void> {
  if (!await notificationManager.isNotificationEnabled()) return;
  const agent = await wantAgent.getWantAgent({ wants: [{ bundleName: 'cn.nua.wenguan.schedule', abilityName: 'EntryAbility' }], operationType: wantAgent.OperationType.START_ABILITY, requestCode: 1240, wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
  // BASIC_TEXT = 0; current SDK's publish request refers to its legacy enum alias.
  await notificationManager.publish({ id: 1240, wantAgent: agent, content: { contentType: 0, normal: { title: '有课表更新', text: '有课表更新' } } });
}
