import { useCallback, useEffect, useMemo, useState } from 'react'
import type { LucideIcon } from 'lucide-react'
import { ChartNoAxesCombined, CircleCheck, FolderOpen, Gamepad2, Globe2, HardDrive, Landmark, LoaderCircle, Network, PawPrint, Play, PlugZap, RefreshCw, RotateCcw, Save, Search, Settings, Shield, ShieldCheck, Square, Swords, Terminal, Users } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import { getSettingChoices } from '../shared/setting-choices'
import type { ConnectionState, HelperState, ServerSnapshot, SettingView } from '../shared/types'
import { palworld } from './bridge'

const categoryIcons: Record<string, LucideIcon> = {
  'World & Time': Globe2, 'Player Balance': Users, 'Pal Balance': PawPrint,
  'Resources & Performance': ChartNoAxesCombined, 'Bases & Guilds': Landmark,
  'PvP & Death': Swords, 'Gameplay Features': Gamepad2, 'Server & Access': Shield,
  Administration: Settings, 'Startup Arguments': Terminal
}

function formatUptime(seconds?: number | null): string {
  if (seconds == null) return '--'
  const days = Math.floor(seconds / 86400), hours = Math.floor((seconds % 86400) / 3600), minutes = Math.floor((seconds % 3600) / 60)
  return days > 0 ? `${days}d ${hours}h` : `${hours}h ${minutes}m`
}

function Metric({ label, value }: { label: string; value: string }) { return <div className="metric"><span>{label}</span><strong>{value}</strong></div> }

function SecretEditor({ setting, onChange }: { setting: SettingView; onChange(value: string): void }) {
  const [open, setOpen] = useState(false), [first, setFirst] = useState(''), [second, setSecond] = useState('')
  const valid = first === second
  const submit = () => { if (!valid) return; onChange(first); setFirst(''); setSecond(''); setOpen(false) }
  return <Dialog open={open} onOpenChange={setOpen}>
    <Button variant="outline" onClick={() => setOpen(true)}>{setting.hasSecret ? 'Change password' : 'Set password'}</Button>
    <DialogContent><DialogTitle>{setting.label}</DialogTitle><DialogDescription>The current value is never shown. Enter the replacement twice to prevent typing mistakes.</DialogDescription>
      <div className="mt-5 space-y-3"><Input type="password" value={first} onChange={(event) => setFirst(event.target.value)} placeholder="New value" autoFocus /><Input type="password" value={second} onChange={(event) => setSecond(event.target.value)} placeholder="Confirm value" onKeyDown={(event) => { if (event.key === 'Enter' && valid) submit() }} />{!valid && second.length > 0 && <p className="text-sm text-red-600">The values do not match.</p>}</div>
      <div className="mt-6 flex justify-end gap-2"><DialogClose asChild><Button variant="outline">Cancel</Button></DialogClose><Button onClick={submit} disabled={!valid}>Apply</Button></div>
    </DialogContent>
  </Dialog>
}

function SettingEditor({ setting, value, onChange }: { setting: SettingView; value: string; onChange(value: string): void }) {
  const choices = getSettingChoices(setting)
  if (choices) return <Select value={value} onValueChange={onChange}><SelectTrigger aria-label={setting.label}><SelectValue /></SelectTrigger><SelectContent>{choices.map((choice) => <SelectItem key={choice} value={choice}>{choice}</SelectItem>)}</SelectContent></Select>
  if (setting.type === 'secret') return <SecretEditor setting={setting} onChange={onChange} />
  return <Input type={setting.type === 'integer' || setting.type === 'number' ? 'number' : 'text'} min={setting.min} max={setting.max} step={setting.type === 'integer' ? 1 : setting.type === 'number' ? 'any' : undefined} value={value} onChange={(event) => onChange(event.target.value)} />
}

function SettingCard({ setting, draft, onChange, onReset }: { setting: SettingView; draft?: string; onChange(value: string): void; onReset(): void }) {
  const value = draft ?? setting.value
  const differsFromDefault = setting.type === 'secret' ? draft !== undefined ? draft !== setting.defaultValue : !setting.isDefault : value !== setting.defaultValue
  return <article className={cn('setting-card', differsFromDefault && 'setting-card-modified')}><div className="min-w-0"><h3>{setting.label}</h3><code>{setting.name}</code><p title={setting.description}>{setting.description}</p></div><div className="setting-editor"><SettingEditor setting={setting} value={value} onChange={onChange} /></div><div className="default-value"><span>Default</span><strong>{setting.type === 'secret' ? (setting.defaultValue ? 'Configured' : 'Empty') : setting.defaultValue || 'Empty'}</strong></div><Button variant="ghost" size="sm" onClick={onReset}><RotateCcw className="size-4" />Reset</Button></article>
}

function ConnectionDialog({ open, required, initialPath, onOpenChange, onConnected }: { open: boolean; required: boolean; initialPath: string; onOpenChange(open: boolean): void; onConnected(): Promise<void> }) {
  const [path, setPath] = useState(initialPath), [state, setState] = useState<ConnectionState | null>(null), [helper, setHelper] = useState<HelperState | null>(null), [busy, setBusy] = useState(false)
  useEffect(() => { if (open) { setPath(initialPath); setState(null); setHelper(null) } }, [initialPath, open])
  const run = async (action: () => Promise<ConnectionState>) => { setBusy(true); try { const next = await action(); setState(next); if (next.path) setPath(next.path); return next } catch (error) { setState({ path, source: 'Connection', valid: false, detail: error instanceof Error ? error.message : String(error) }); return null } finally { setBusy(false) } }
  const choose = async () => { setBusy(true); try { const next = await palworld.chooseConnection(); if (next.path) { setState(next); setPath(next.path) } return next } catch (error) { setState({ path, source: 'Connection', valid: false, detail: error instanceof Error ? error.message : String(error) }); return null } finally { setBusy(false) } }
  const detect = async () => { const detected = await run(() => palworld.detectConnection()); if (!detected?.valid) await choose() }
  const save = async () => { const tested = await run(() => palworld.testConnection(path)); if (!tested?.valid) return; const saved = await run(() => palworld.saveConnection(tested.path, true)); if (!saved?.valid) return; await onConnected(); const helperState = await palworld.getHelperStatus(); if (helperState.canInstall) setHelper(helperState); else onOpenChange(false) }
  const install = async () => { setBusy(true); try { setHelper(await palworld.installHelper()) } catch (error) { setHelper({ installed: false, canInstall: true, detail: error instanceof Error ? error.message : String(error) }) } finally { setBusy(false) } }
  return <Dialog open={open} onOpenChange={(next) => { if (next || !required) onOpenChange(next) }}><DialogContent className={cn('w-[min(92vw,620px)]', required && '[&>button]:hidden')}><DialogTitle>Connect to your Palworld server</DialogTitle><DialogDescription>Choose where the dedicated server files live. The app will remember this location, and you can change it later.</DialogDescription>
    <div className="connection-options"><button type="button" onClick={() => void detect()} disabled={busy}><HardDrive className="size-5" /><span><strong>Use this machine</strong><small>Detect nearby, then browse if it is not found.</small></span></button><button type="button" onClick={() => void choose()} disabled={busy}><FolderOpen className="size-5" /><span><strong>Choose server folder</strong><small>Browse to the local Palworld server folder.</small></span></button></div>
    <label className="connection-field"><span><Network className="size-4" /> Server folder or network share</span><div className="connection-input"><Input value={path} onChange={(event) => { setPath(event.target.value); setState(null) }} placeholder="D:\\PalServer or \\\\SERVER\\PalServer" autoFocus /><Button type="button" variant="outline" size="icon" aria-label="Browse for server folder" title="Browse for server folder" onClick={() => void choose()} disabled={busy}><FolderOpen className="size-4" /></Button></div></label>
    {state && <div className={cn('connection-result', state.valid ? 'connection-valid' : 'connection-invalid')}><PlugZap className="size-4" /><div><strong>{state.valid ? 'Connection ready' : 'Connection not ready'}</strong><span>{state.detail}</span></div></div>}
    {helper && <div className={cn('helper-install', helper.installed ? 'connection-valid' : 'helper-ready')}>{helper.installed ? <CircleCheck className="size-5" /> : <ShieldCheck className="size-5" />}<div><strong>{helper.installed ? 'Server helper installed' : 'Install server helper'}</strong><span>{helper.detail}</span></div></div>}
    <div className="mt-6 flex justify-end gap-2">{helper ? <><Button variant="outline" onClick={() => onOpenChange(false)}>{helper.installed ? 'Done' : 'Finish later'}</Button><Button onClick={() => void install()} disabled={busy}>{busy ? <LoaderCircle className="size-4 animate-spin" /> : <ShieldCheck className="size-4" />}{helper.installed ? 'Reinstall / Update Helper' : 'Install Server Helper'}</Button></> : <>{!required && <DialogClose asChild><Button variant="outline">Cancel</Button></DialogClose>}<Button variant="outline" onClick={() => void run(() => palworld.testConnection(path))} disabled={busy || !path.trim()}>Test connection</Button><Button onClick={() => void save()} disabled={busy || !path.trim()}>{busy && <LoaderCircle className="size-4 animate-spin" />}Use this location</Button></>}</div>
  </DialogContent></Dialog>
}

export default function App() {
  const [snapshot, setSnapshot] = useState<ServerSnapshot | null>(null), [selectedCategory, setSelectedCategory] = useState('Bases & Guilds'), [search, setSearch] = useState('')
  const [drafts, setDrafts] = useState<Record<string, string>>({}), [busy, setBusy] = useState(false)
  const [activeCommand, setActiveCommand] = useState<'start' | 'stop' | 'restart' | 'status' | null>(null)
  const [notice, setNotice] = useState<{ tone: 'success' | 'error' | 'info'; text: string } | null>(null)
  const [connectionOpen, setConnectionOpen] = useState(false), [connectionPath, setConnectionPath] = useState('')
  const load = useCallback(async (keepDrafts = false) => { try { const next = await palworld.loadSnapshot(); setSnapshot(next); setConnectionPath(next.shareRoot); if (!keepDrafts) setDrafts({}); const categories = new Set(next.settings.map((item) => item.category)); if (!categories.has(selectedCategory)) setSelectedCategory(next.settings[0]?.category ?? ''); setNotice(null); return true } catch (error) { setNotice({ tone: 'error', text: error instanceof Error ? error.message : String(error) }); return false } }, [selectedCategory])
  useEffect(() => { void (async () => { const connection = await palworld.getConnection(); setConnectionPath(connection.path); const loaded = connection.valid && await load(); if (!loaded) setConnectionOpen(true) })() }, [])
  useEffect(() => { const timer = window.setInterval(() => { if (Object.keys(drafts).length === 0) void load(true) }, 3000); return () => window.clearInterval(timer) }, [drafts, load])
  const categories = useMemo(() => snapshot ? [...new Set(snapshot.settings.map((item) => item.category))] : [], [snapshot])
  const visibleSettings = useMemo(() => { if (!snapshot) return []; const needle = search.trim().toLowerCase(); return snapshot.settings.filter((setting) => setting.category === selectedCategory && (!needle || `${setting.label} ${setting.name} ${setting.description}`.toLowerCase().includes(needle))) }, [search, selectedCategory, snapshot])
  const setDraft = (setting: SettingView, value: string) => setDrafts((current) => { const next = { ...current }; if (value === setting.value) delete next[setting.key]; else next[setting.key] = value; return next })
  const save = async (restart: boolean) => { if (!snapshot || Object.keys(drafts).length === 0) return; setBusy(true); try { const result = await palworld.saveSettings({ changes: drafts, expectedIniHash: snapshot.iniHash, expectedStartupHash: snapshot.startupHash }); if (restart) await palworld.sendCommand('restart'); await load(); setNotice({ tone: 'success', text: restart ? `Saved ${result.changed} settings. Restart requested.` : `Saved ${result.changed} settings. Restart required.` }) } catch (error) { setNotice({ tone: 'error', text: error instanceof Error ? error.message : String(error) }) } finally { setBusy(false) } }
  const command = async (value: 'start' | 'stop' | 'restart' | 'status') => { if ((value === 'stop' || value === 'restart') && !window.confirm(`${value === 'stop' ? 'Stop' : 'Restart'} the Palworld server? Connected players will receive a shutdown notice.`)) return; setBusy(true); setActiveCommand(value); try { await palworld.sendCommand(value); if (value !== 'status') { const state = value === 'start' ? 'Starting' : value === 'stop' ? 'Stopping' : 'Restarting'; setSnapshot((current) => current ? { ...current, status: { ...current.status, state, detail: `${state} request submitted.` } } : current) } setNotice({ tone: 'info', text: `${value[0].toUpperCase()}${value.slice(1)} request submitted.` }); if (value === 'status') { await new Promise((resolve) => window.setTimeout(resolve, 900)); await load(true) } else window.setTimeout(() => void load(true), 2500) } catch (error) { setNotice({ tone: 'error', text: error instanceof Error ? error.message : String(error) }) } finally { setActiveCommand(null); setBusy(false) } }
  const status = snapshot?.status, running = status?.state === 'Running', transitioning = status?.state === 'Starting' || status?.state === 'Stopping' || status?.state === 'Restarting'
  return <main className="app-shell"><header className="app-header"><div><h1>Palworld Dedicated Server</h1><p>Server control and configuration</p></div><Button variant="outline" onClick={() => setConnectionOpen(true)}><Settings className="size-4" />Connection</Button></header>
    <section className="dashboard"><div className="status-block"><span className={cn('status-dot', transitioning && 'animate-pulse', running ? 'bg-emerald-500' : status?.state === 'Stopped' ? 'bg-red-500' : transitioning ? 'bg-blue-500' : 'bg-amber-500')} /><div><strong className={cn(running ? 'text-emerald-700' : status?.state === 'Stopped' ? 'text-red-600' : transitioning ? 'text-blue-600' : 'text-amber-600')}>{status?.state ?? 'Connecting'}</strong><span>{status?.detail}</span></div></div><div className="metrics"><Metric label="Players" value={status?.currentPlayers != null && status.maxPlayers != null ? `${status.currentPlayers} / ${status.maxPlayers}` : '--'} /><Metric label="Uptime" value={formatUptime(status?.uptimeSeconds)} /><Metric label="Server FPS" value={status?.serverFps != null ? Number(status.serverFps).toFixed(1) : '--'} /></div><div className="control-actions"><Button variant="success" size="lg" onClick={() => void command('start')} disabled={busy || transitioning}><Play className="size-5 fill-current" />Start</Button><Button variant="danger" size="lg" onClick={() => void command('stop')} disabled={busy || transitioning}><Square className="size-5 fill-current" />Stop</Button><Button variant="warning" size="lg" onClick={() => void command('restart')} disabled={busy || transitioning}><RotateCcw className="size-5" />Restart</Button><Button variant="outline" size="lg" className="border-blue-500 text-blue-600" onClick={() => void command('status')} disabled={busy || transitioning}>{activeCommand === 'status' ? <LoaderCircle className="size-5 animate-spin" /> : <RefreshCw className="size-5" />}{activeCommand === 'status' ? 'Refreshing…' : 'Refresh'}</Button></div></section>
    <section className="workspace"><aside className="sidebar">{categories.map((category) => { const Icon = categoryIcons[category] ?? Settings; return <button type="button" key={category} className={cn('category-button', selectedCategory === category && 'category-active')} aria-current={selectedCategory === category ? 'page' : undefined} onClick={() => setSelectedCategory(category)}><Icon className="size-5" /><span>{category}</span></button> })}</aside><div className="content"><div className="content-header"><div><h2>{selectedCategory}</h2><div className="search"><Search className="size-4" /><Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search settings" /></div></div><div className="save-actions"><Button variant="outline" onClick={() => void load()} disabled={busy}><RefreshCw className="size-4" />Reload</Button><Button variant="outline" className="border-blue-500 text-blue-600" onClick={() => void save(false)} disabled={busy || Object.keys(drafts).length === 0}><Save className="size-4" />Save</Button><Button onClick={() => void save(true)} disabled={busy || Object.keys(drafts).length === 0}>{busy ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />}Save & Restart</Button></div></div>{notice && <div className={cn('notice', notice.tone === 'error' ? 'notice-error' : notice.tone === 'success' ? 'notice-success' : 'notice-info')}>{notice.text}</div>}<div className="settings-list">{visibleSettings.map((setting) => <SettingCard key={setting.key} setting={setting} draft={drafts[setting.key]} onChange={(value) => setDraft(setting, value)} onReset={() => setDraft(setting, setting.defaultValue)} />)}{visibleSettings.length === 0 && <div className="empty-state">No settings match this search.</div>}</div></div></section>
    <ConnectionDialog open={connectionOpen} required={!snapshot} initialPath={connectionPath} onOpenChange={setConnectionOpen} onConnected={async () => { await load(); }} />
  </main>
}
