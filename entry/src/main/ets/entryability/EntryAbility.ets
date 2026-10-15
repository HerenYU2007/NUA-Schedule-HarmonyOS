import { UIAbility, Configuration, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { refreshAllForms } from '../services/Forms';
import { loadApp } from '../services/AppStore';
import { loadClock } from '../services/ClockStore';
export default class EntryAbility extends UIAbility {
  onCreate(want: Want): void { try { loadClock(this.context); } catch (_) {} this.receive(want); }
  onNewWant(want: Want): void { this.receive(want); }
  private receive(want: Want): void { const day = Number(want.parameters?.cardWeek ?? 0); if (Number.isInteger(day) && day > 0 && day < 100000) AppStorage.setOrCreate('cardWeek', day); }
  onWindowStageCreate(stage: window.WindowStage): void {
    if (!AppStorage.has('cardWeek')) AppStorage.setOrCreate('cardWeek', 0);
    if (!AppStorage.has('scheduleRevision')) AppStorage.setOrCreate('scheduleRevision', 0);
    try {
      const theme = loadApp(this.context).preferences.theme;
      this.context.getApplicationContext().setColorMode(theme === 2 ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : theme === 1 ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (_) { /* Preserve unreadable preferences; Index displays the error without overwriting. */ }
    AppStorage.setOrCreate('systemDark', this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    stage.loadContent('pages/Index');
  }
  onConfigurationUpdate(configuration: Configuration): void {
    AppStorage.setOrCreate('systemDark', configuration.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    refreshAllForms(this.context).catch(() => {});
  }
  onForeground(): void { refreshAllForms(this.context).catch(() => {}); }
}
