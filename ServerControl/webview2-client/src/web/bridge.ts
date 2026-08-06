import type { ConnectionState, HelperState, PalworldApi, SaveRequest, SaveResult, ServerSnapshot, ServerCommand } from '../shared/types'

type BridgeMethod = 'snapshot.load' | 'settings.save' | 'command.send' | 'connection.current' | 'connection.detect' | 'connection.choose' | 'connection.test' | 'connection.save' | 'helper.status' | 'helper.install'
type PendingCall = { resolve(value: unknown): void; reject(reason: Error): void }
type BridgeResponse = { id: string; ok: boolean; result?: unknown; error?: string }

declare global {
  interface Window {
    chrome?: { webview?: { postMessage(message: unknown): void; addEventListener(type: 'message', listener: (event: MessageEvent<BridgeResponse>) => void): void } }
  }
}

const pending = new Map<string, PendingCall>()
let nextId = 1

window.chrome?.webview?.addEventListener('message', (event) => {
  const response = event.data
  if (!response || typeof response.id !== 'string' || typeof response.ok !== 'boolean') return
  const call = pending.get(response.id)
  if (!call) return
  pending.delete(response.id)
  if (response.ok) call.resolve(response.result)
  else call.reject(new Error(response.error || 'The native host rejected the request.'))
})

function invoke<T>(method: BridgeMethod, params?: unknown): Promise<T> {
  const webview = window.chrome?.webview
  if (!webview) return Promise.reject(new Error('The native WebView2 host is unavailable.'))
  const id = String(nextId++)
  return new Promise<T>((resolve, reject) => {
    pending.set(id, { resolve: (value) => resolve(value as T), reject })
    webview.postMessage({ id, method, params })
  })
}

export const palworld: PalworldApi = {
  loadSnapshot: () => invoke<ServerSnapshot>('snapshot.load'),
  saveSettings: (request: SaveRequest) => invoke<SaveResult>('settings.save', request),
  sendCommand: (command: ServerCommand) => invoke<string>('command.send', { command }),
  getConnection: () => invoke<ConnectionState>('connection.current'),
  detectConnection: () => invoke<ConnectionState>('connection.detect'),
  chooseConnection: () => invoke<ConnectionState>('connection.choose'),
  testConnection: (path: string) => invoke<ConnectionState>('connection.test', { path, remember: false }),
  saveConnection: (path: string, remember = true) => invoke<ConnectionState>('connection.save', { path, remember }),
  getHelperStatus: () => invoke<HelperState>('helper.status'),
  installHelper: () => invoke<HelperState>('helper.install')
}
