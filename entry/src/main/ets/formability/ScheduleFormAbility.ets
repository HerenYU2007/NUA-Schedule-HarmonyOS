import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { formEpoch } from '../model/Schedule';
import { formChoices, saveChoices, FormChoice } from '../services/Store';
import { binding, refreshOne, namedChoice, formDiagnostic } from '../services/Forms';
import { formCommand } from '../model/FormCommand';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
export default class ScheduleFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const id = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    const choices = formChoices(this.context).filter((v: FormChoice) => v.id !== id);
    const dimension = Number(want.parameters?.[formInfo.FormParam.DIMENSION_KEY] ?? 3);
    const choice = namedChoice(id, String(want.parameters?.[formInfo.FormParam.NAME_KEY] || 'TodaySchedule'), dimension);
    this.size(choice, want.parameters);
    choices.push(choice);
    saveChoices(this.context, choices);
    formProvider.setFormNextRefreshTime(id, 5).catch(() => {});
    return binding(this.context, choice);
  }
  onCastToNormalForm(id: string): void { this.onUpdateForm(id); }
  private size(choice: FormChoice, parameters?: Record<string, Object>): void {
    const width = Number(parameters?.[formInfo.FormParam.WIDTH_KEY] ?? 0);
    const height = Number(parameters?.[formInfo.FormParam.HEIGHT_KEY] ?? 0);
    // Use aspect ratio so host sizes work whether delivered in physical pixels or vp.
    // Conservative 320-vp phone width avoids density-dependent overfilling.
    if (width > 0 && height > 0) choice.height = Math.max(100, Math.min(600, height / width * 320));
  }
  onUpdateForm(id: string, parameters?: Record<string, Object>): void {
    this.updateRecover(id, parameters).catch(() => formDiagnostic(this.context, '更新失败'));
  }
  private async updateRecover(id: string, parameters?: Record<string, Object>): Promise<void> {
    const choices = formChoices(this.context); let choice = choices.find((v: FormChoice) => v.id === id);
    if (!choice) { const info = await formProvider.getPublishedRunningFormInfoById(id); choice = namedChoice(id, info.formName, info.dimension); choices.push(choice); }
    this.size(choice, parameters); saveChoices(this.context, choices); await refreshOne(this.context, choice); formDiagnostic(this.context, '更新成功');
  }
  onFormEvent(id: string, message: string): void {
    hilog.info(0xFF10, 'NuaScheduleForm', 'event received');
    try {
      const action = formCommand(message);
      if (!action) { hilog.warn(0xFF10, 'NuaScheduleForm', 'unrecognized command'); return; }
      const choices = formChoices(this.context);
      const choice = choices.find((v: FormChoice) => v.id === id);
      if (!choice) { this.updateRecover(id).then(() => this.onFormEvent(id, message)).catch(() => formDiagnostic(this.context, '交互时恢复失败')); return; }
      if (action === 'previousWeek') choice.weekOffset = Math.max(-53, (choice.weekOffset || 0) - 1);
      else if (action === 'nextWeek') choice.weekOffset = Math.min(53, (choice.weekOffset || 0) + 1);
      else if (action === 'currentWeek') choice.weekOffset = 0;
      else choice.offset = action === 'today' ? 0 : action === 'tomorrow' ? 1 : -1;
      formDiagnostic(this.context, '交互：' + action);
      choice.date = formEpoch();
      saveChoices(this.context, choices);
      refreshOne(this.context, choice).then(() => {
        hilog.info(0xFF10, 'NuaScheduleForm', 'card updated: %{public}s', action);
      }).catch((error: BusinessError) => {
        hilog.error(0xFF10, 'NuaScheduleForm', 'card update failed: %{public}d', error.code);
      });
    } catch (_) { hilog.error(0xFF10, 'NuaScheduleForm', 'card event storage failed'); }
  }
  onRemoveForm(id: string): void {
    saveChoices(this.context, formChoices(this.context).filter((v: FormChoice) => v.id !== id));
  }
}
