export type SettingType = 'boolean' | 'integer' | 'number' | 'enum' | 'string' | 'secret' | 'raw'

export interface SettingMetadata {
  name: string
  category: string
  label: string
  description: string
  type: SettingType
  default: string | number | boolean
  min?: number
  max?: number
  options?: string[]
  source: 'ini' | 'startup'
}

export interface SettingView extends SettingMetadata {
  key: string
  value: string
  defaultValue: string
  isDefault: boolean
  hasSecret?: boolean
}

export interface ServerStatus {
  state: 'Running' | 'Stopped' | 'Starting' | 'Stopping' | 'Restarting' | 'Unavailable' | 'Unknown'
  detail: string
  currentPlayers?: number | null
  maxPlayers?: number | null
  uptimeSeconds?: number | null
  serverFps?: number | null
}

export interface ServerSnapshot {
  shareRoot: string
  status: ServerStatus
  settings: SettingView[]
  iniHash: string
  startupHash: string | null
}

export interface SaveRequest {
  changes: Record<string, string>
  expectedIniHash: string
  expectedStartupHash: string | null
}

export interface SaveResult { changed: number; backups: string[] }
export type ServerCommand = 'start' | 'stop' | 'restart' | 'status'

export interface ConnectionState {
  path: string
  source: string
  valid: boolean
  detail: string
}

export interface HelperState {
  installed: boolean
  canInstall: boolean
  detail: string
}

export interface PalworldApi {
  loadSnapshot(): Promise<ServerSnapshot>
  saveSettings(request: SaveRequest): Promise<SaveResult>
  sendCommand(command: ServerCommand): Promise<string>
  getConnection(): Promise<ConnectionState>
  detectConnection(): Promise<ConnectionState>
  chooseConnection(): Promise<ConnectionState>
  testConnection(path: string): Promise<ConnectionState>
  saveConnection(path: string, remember?: boolean): Promise<ConnectionState>
  getHelperStatus(): Promise<HelperState>
  installHelper(): Promise<HelperState>
}
