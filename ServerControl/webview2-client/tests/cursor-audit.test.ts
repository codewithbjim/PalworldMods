import assert from 'node:assert/strict'
import { readdirSync, readFileSync } from 'node:fs'
import { test } from 'node:test'
import { join } from 'node:path'

const read = (path: string) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
const button = read('src/web/components/ui/button.tsx')
const input = read('src/web/components/ui/input.tsx')
const select = read('src/web/components/ui/select.tsx')
const dialog = read('src/web/components/ui/dialog.tsx')
const app = read('src/web/App.tsx')
const styles = read('src/web/styles.css')
const frontendSource = readdirSync(new URL('../src/web', import.meta.url), { recursive: true, withFileTypes: true })
  .filter((entry) => entry.isFile() && entry.name.endsWith('.tsx'))
  .map((entry) => readFileSync(join(entry.parentPath, entry.name), 'utf8'))
  .join('\n')

test('shared button variants distinguish enabled and disabled cursors', () => {
  assert.match(button, /cursor-pointer/)
  assert.match(button, /disabled:cursor-not-allowed/)
  assert.doesNotMatch(button, /disabled:pointer-events-none/)
})

test('text and numeric fields retain text selection cursors', () => {
  assert.match(input, /cursor-text/)
  assert.match(styles, /input, textarea \{ cursor: text; \}/)
})

test('select triggers, items, and scroll controls expose interactive cursors', () => {
  assert.match(select, /SelectPrimitive\.Trigger[\s\S]*cursor-pointer/)
  assert.match(select, /SelectPrimitive\.Item[\s\S]*cursor-pointer/)
  assert.match(select, /data-\[disabled\]:cursor-not-allowed/)
  assert.equal((select.match(/Scroll(?:Up|Down)Button className="[^"]*cursor-pointer/g) ?? []).length, 2)
})

test('dialog and sidebar controls include pointer, focus, and semantic states', () => {
  assert.match(dialog, /DialogPrimitive\.Close aria-label="Close dialog" className="[^"]*cursor-pointer[^"]*focus-visible:ring-2/)
  assert.match(app, /<button type="button"[^>]*className=\{cn\('category-button'/)
  assert.match(app, /aria-current=\{selectedCategory === category \? 'page'/)
  assert.match(styles, /\.category-button:focus-visible/)
})

test('global interaction policy covers links, native selects, roles, and disabled actions', () => {
  assert.match(styles, /a\[href\]/)
  assert.match(styles, /select:not\(:disabled\)/)
  assert.match(styles, /\[role="button"\]/)
  assert.match(styles, /\[role="link"\]/)
  assert.match(styles, /\[role="option"\]/)
  assert.match(styles, /cursor: not-allowed/)
})

test('application click handlers are not attached to divs, spans, labels, or articles', () => {
  assert.doesNotMatch(frontendSource, /<(?:div|span|label|article)\b[^>]*\bonClick=/)
  assert.doesNotMatch(frontendSource, /role=["'](?:button|link)["']/)
  assert.doesNotMatch(frontendSource, /cursor-default/)
})
