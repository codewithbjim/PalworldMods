import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  decodePalValue,
  encodePalValue,
  readPalWorldSettings,
  splitPalOptionSegments,
  writePalWorldSettings,
} from '../src/shared/pal-config.ts'
import type { SettingMetadata } from '../src/shared/types.ts'

function metadata(overrides: Partial<SettingMetadata> & Pick<SettingMetadata, 'name' | 'type'>): SettingMetadata {
  return {
    category: 'Test',
    label: overrides.name,
    description: '',
    default: '',
    source: 'ini',
    ...overrides,
  }
}

test('round-trips quoted commas, escaped quotes, and nested tuples exactly', () => {
  const content = '[/Script/Pal.PalGameWorldSettings]\r\nOptionSettings=(ServerName="Hello, \\"world\\"",Nested=(Outer=(A,"B,C"),Inner=(D,E)),CrossplayPlatforms=(Steam,Xbox,PS5,Mac),RCONEnabled=False)\r\n'
  const document = readPalWorldSettings(content)

  assert.equal(document.entries.get('ServerName'), '"Hello, \\"world\\""')
  assert.equal(document.entries.get('Nested'), '(Outer=(A,"B,C"),Inner=(D,E))')
  assert.equal(document.entries.get('CrossplayPlatforms'), '(Steam,Xbox,PS5,Mac)')
  assert.equal(writePalWorldSettings(document, new Map()), content)
})

test('splits only top-level commas', () => {
  assert.deepEqual(
    splitPalOptionSegments('Name="A,B",Tuple=(A,(B,C),"D,E"),Enabled=True'),
    ['Name="A,B"', 'Tuple=(A,(B,C),"D,E")', 'Enabled=True'],
  )
})

test('changes one value without losing or normalizing unknown INI values', () => {
  const content = 'before\nOptionSettings=(Known=1,FutureSetting=(A,(B,C)),FutureString="A,B",FutureRaw=Unrecognized)\nafter'
  const document = readPalWorldSettings(content)
  const output = writePalWorldSettings(document, new Map([['Known', '2']]))

  assert.equal(output, 'before\nOptionSettings=(Known=2,FutureSetting=(A,(B,C)),FutureString="A,B",FutureRaw=Unrecognized)\nafter')
})

test('rejects changes to settings absent from the loaded document', () => {
  const document = readPalWorldSettings('OptionSettings=(Known=1)')
  assert.throws(() => writePalWorldSettings(document, new Map([['Injected', '2']])), /Cannot update missing setting/)
})

test('validates and canonicalizes enum and boolean values', () => {
  const enumMetadata = metadata({ name: 'DeathPenalty', type: 'enum', options: ['None', 'Item', 'All'] })
  const booleanMetadata = metadata({ name: 'RCONEnabled', type: 'boolean' })

  assert.equal(encodePalValue('item', enumMetadata), 'Item')
  assert.equal(encodePalValue('false', booleanMetadata), 'False')
  assert.throws(() => encodePalValue('Anything', enumMetadata), /must be one of/)
  assert.throws(() => encodePalValue('yes', booleanMetadata), /must be True or False/)
})

test('escapes and restores quoted string and secret values', () => {
  for (const type of ['string', 'secret'] as const) {
    const setting = metadata({ name: 'QuotedValue', type })
    const encoded = encodePalValue('Operator "North" \\ Realm', setting)
    assert.equal(encoded, '"Operator \\"North\\" \\\\ Realm"')
    assert.equal(decodePalValue(encoded, type), 'Operator "North" \\ Realm')
  }
})

test('validates integer and number ranges deterministically', () => {
  const integer = metadata({ name: 'Players', type: 'integer', min: 1, max: 32 })
  const number = metadata({ name: 'Rate', type: 'number', min: 0, max: 2 })

  assert.equal(encodePalValue('032', integer), '32')
  assert.equal(encodePalValue('1.500000', number), '1.5')
  assert.throws(() => encodePalValue('0', integer), /at least 1/)
  assert.throws(() => encodePalValue('Infinity', number), /finite number/)
})
