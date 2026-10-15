// The 2*4 daily card reserves room for two compact, two-line lessons.
export function dailyCardCapacity(height: number): number {
  const available = Number.isFinite(height) ? height : 180;
  return available < 240 ? 2 : Math.max(2, Math.floor((available - 78) / 65));
}
