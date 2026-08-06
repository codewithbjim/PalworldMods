import type { SettingMetadata } from './types.ts'

/** Returns dropdown choices, or null when the setting's data shape requires text editing. */
export function getSettingChoices(setting: Pick<SettingMetadata, 'type' | 'options'>): string[] | null {
  if (setting.options?.length) return [...setting.options]
  if (setting.type === 'boolean') return ['True', 'False']
  return null
}
