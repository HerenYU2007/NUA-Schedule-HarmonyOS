import { common } from '@kit.AbilityKit';
import { AppState, defaultState, validState } from '../model/AppModel';
import { readJson as atomicRead, writeJson as atomicWrite } from './AtomicStore';
export function readJson(context: common.Context, name: string, fallback: string): string { return atomicRead(context, name, fallback); }
export function writeJson(context: common.Context, name: string, value: string): void { atomicWrite(context, name, value); }
export function loadApp(context: common.Context): AppState { return validState(JSON.parse(readJson(context, 'app-state.json', JSON.stringify(defaultState()))) as AppState); }
export function saveApp(context: common.Context, state: AppState): void { writeJson(context, 'app-state.json', JSON.stringify(validState(state))); }
