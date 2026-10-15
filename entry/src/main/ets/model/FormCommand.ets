interface CommandParams { command?: string; action?: string; }
interface CommandEnvelope { command?: string; action?: string; params?: CommandParams; }
function known(value: string | undefined): string {
  return value === 'today' || value === 'tomorrow' || value === 'refresh' || value === 'previousWeek' || value === 'nextWeek' || value === 'currentWeek' ? value : '';
}
// Hosts may deliver the params object itself or an action envelope. Never use
// the framework's top-level action ("message") as the schedule command.
export function formCommand(message: string): string {
  if (message.length > 2048) return '';
  try {
    const value = JSON.parse(message) as CommandEnvelope;
    if (!value || typeof value !== 'object') return '';
    return known(value.params?.command) || known(value.params?.action) || known(value.command) || known(value.action);
  } catch (_) { return ''; }
}
