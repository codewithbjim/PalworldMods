import type { SettingMetadata, SettingType } from './types.ts'

export interface PalDocument {
  prefix: string
  suffix: string
  entries: Map<string, string>
  order: string[]
}

function isEscaped(text: string, index: number): boolean {
  let backslashes = 0
  for (let behind = index - 1; behind >= 0 && text[behind] === '\\'; behind -= 1) backslashes += 1
  return backslashes % 2 !== 0
}

/** Splits only top-level commas, preserving quoted strings and tuple contents byte-for-byte. */
export function splitPalOptionSegments(text: string): string[] {
  const segments: string[] = []
  let segmentStart = 0
  let depth = 0
  let inQuotes = false

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index]
    if (character === '"' && !isEscaped(text, index)) {
      inQuotes = !inQuotes
      continue
    }
    if (inQuotes) continue
    if (character === '(') depth += 1
    else if (character === ')') depth -= 1
    else if (character === ',' && depth === 0) {
      segments.push(text.slice(segmentStart, index))
      segmentStart = index + 1
    }
  }

  segments.push(text.slice(segmentStart))
  return segments
}

/** Parses OptionSettings while retaining all surrounding and unknown INI content. */
export function readPalWorldSettings(content: string): PalDocument {
  const marker = 'OptionSettings=('
  const markerIndex = content.indexOf(marker)
  if (markerIndex < 0) throw new Error('OptionSettings section was not found.')

  const innerStart = markerIndex + marker.length
  let depth = 1
  let inQuotes = false
  let innerEnd = -1

  for (let index = innerStart; index < content.length; index += 1) {
    const character = content[index]
    if (character === '"' && !isEscaped(content, index)) {
      inQuotes = !inQuotes
      continue
    }
    if (inQuotes) continue
    if (character === '(') depth += 1
    else if (character === ')') {
      depth -= 1
      if (depth === 0) {
        innerEnd = index
        break
      }
    }
  }

  if (innerEnd < 0) throw new Error('OptionSettings closing parenthesis was not found.')

  const entries = new Map<string, string>()
  const order: string[] = []
  for (const segment of splitPalOptionSegments(content.slice(innerStart, innerEnd))) {
    const equalsIndex = segment.indexOf('=')
    if (equalsIndex <= 0) throw new Error(`Invalid OptionSettings segment: ${segment}`)
    const name = segment.slice(0, equalsIndex).trim()
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error(`Invalid setting name: ${name}`)
    if (entries.has(name)) throw new Error(`Duplicate setting found: ${name}`)
    entries.set(name, segment.slice(equalsIndex + 1))
    order.push(name)
  }

  return {
    prefix: content.slice(0, innerStart),
    suffix: content.slice(innerEnd),
    entries,
    order,
  }
}

/** Applies known changes without normalizing or dropping any untouched setting. */
export function writePalWorldSettings(document: PalDocument, changes: ReadonlyMap<string, string>): string {
  for (const name of changes.keys()) {
    if (!document.entries.has(name)) throw new Error(`Cannot update missing setting: ${name}`)
  }
  const segments = document.order.map((name) => `${name}=${changes.get(name) ?? document.entries.get(name) ?? ''}`)
  return document.prefix + segments.join(',') + document.suffix
}

export function unquotePalValue(rawValue: string): string {
  if (rawValue.length >= 2 && rawValue.startsWith('"') && rawValue.endsWith('"')) {
    return rawValue.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, '\\')
  }
  return rawValue
}

export function decodePalValue(rawValue: string, type: SettingType): string {
  return type === 'string' || type === 'secret' ? unquotePalValue(rawValue) : rawValue
}

export function encodePalValue(value: string, metadata: SettingMetadata): string {
  switch (metadata.type) {
    case 'boolean':
      if (!/^(true|false)$/i.test(value)) throw new Error(`${metadata.name} must be True or False.`)
      return value.toLowerCase() === 'true' ? 'True' : 'False'
    case 'integer': {
      if (!/^-?\d+$/.test(value.trim())) throw new Error(`${metadata.name} must be a whole number.`)
      const parsed = Number(value)
      if (!Number.isSafeInteger(parsed)) throw new Error(`${metadata.name} is outside the supported whole-number range.`)
      validateRange(parsed, metadata)
      return String(parsed)
    }
    case 'number': {
      const parsed = Number(value)
      if (!Number.isFinite(parsed) || value.trim() === '') throw new Error(`${metadata.name} must be a finite number.`)
      validateRange(parsed, metadata)
      return trimNumber(parsed)
    }
    case 'enum': {
      const option = metadata.options?.find((candidate) => candidate.toLowerCase() === value.toLowerCase())
      if (!option) throw new Error(`${metadata.name} must be one of: ${(metadata.options ?? []).join(', ')}.`)
      return option
    }
    case 'string':
    case 'secret':
      return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`
    case 'raw':
      return value
  }
}

function validateRange(value: number, metadata: SettingMetadata): void {
  if (metadata.min !== undefined && value < metadata.min) throw new Error(`${metadata.name} must be at least ${metadata.min}.`)
  if (metadata.max !== undefined && value > metadata.max) throw new Error(`${metadata.name} must be at most ${metadata.max}.`)
}

export function trimNumber(value: number): string {
  return value.toFixed(6).replace(/\.?0+$/, '')
}

export function displayValue(value: string, metadata: SettingMetadata): string {
  if (metadata.type !== 'number') return value
  const parsed = Number(value)
  return Number.isFinite(parsed) ? trimNumber(parsed) : value
}
