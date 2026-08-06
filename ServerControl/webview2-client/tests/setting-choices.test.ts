import assert from 'node:assert/strict'
import { test } from 'node:test'
import { getSettingChoices } from '../src/shared/setting-choices.ts'

test('renders every declared metadata enum as a dropdown', () => {
  assert.deepEqual(getSettingChoices({ type: 'enum', options: ['None', 'Item', 'All'] }), ['None', 'Item', 'All'])
})

test('renders every Boolean as a True/False dropdown', () => {
  assert.deepEqual(getSettingChoices({ type: 'boolean' }), ['True', 'False'])
})

test('does not allow callers to mutate metadata choices through the result', () => {
  const options = ['Steam', 'Xbox']
  const choices = getSettingChoices({ type: 'enum', options })
  choices?.push('PS5')
  assert.deepEqual(options, ['Steam', 'Xbox'])
})

test('leaves genuinely free-form, list, and tuple values as text inputs', () => {
  assert.equal(getSettingChoices({ type: 'string' }), null)
  assert.equal(getSettingChoices({ type: 'secret' }), null)
  assert.equal(getSettingChoices({ type: 'raw' }), null)
})
