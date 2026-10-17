import { parseJSONSource } from './json-input.js'

const need = (ok, message) => { if (!ok) throw new Error(message) }
const unsigned = text => text.replace(/^0+/u, '') || '0'
// Add a bounded coefficient-length adjustment to an arbitrarily long exponent.
// Work is linear in the token length; no powers, floating point or huge BigInts.
function shiftExponent(text, shift) {
  const negative = text.startsWith('-'), digits = unsigned(text.replace(/^[+-]/u, ''))
  if (!shift) return (negative && digits !== '0' ? '-' : '') + digits
  const adjustment = String(Math.abs(shift)), same = negative === (shift < 0)
  let a = digits, b = adjustment, sign = negative
  if (!same && (a.length < b.length || a.length === b.length && a < b)) { [a, b] = [b, a]; sign = shift < 0 }
  const result = []; let carry = 0
  for (let i = a.length - 1, j = b.length - 1; i >= 0 || j >= 0; i--, j--) {
    const x = i >= 0 ? a.charCodeAt(i) - 48 : 0, y = j >= 0 ? b.charCodeAt(j) - 48 : 0
    const value = same ? x + y + carry : x - y - carry
    result.push(String((value + 10) % 10)); carry = same ? Math.floor(value / 10) : value < 0 ? 1 : 0
  }
  if (same && carry) result.push('1')
  const value = unsigned(result.reverse().join(''))
  return (sign && value !== '0' ? '-' : '') + value
}
function decimalKey(token) {
  const [mantissa, exponent = '0'] = token.toLowerCase().split('e')
  const negative = mantissa.startsWith('-'), body = negative ? mantissa.slice(1) : mantissa
  const dot = body.indexOf('.'), fraction = dot < 0 ? 0 : body.length - dot - 1
  const coefficient = unsigned(body.replace('.', ''))
  if (coefficient === '0') return '0'
  const significant = coefficient.replace(/0+$/u, '')
  return (negative ? '-' : '') + significant + 'e' + shiftExponent(exponent, coefficient.length - significant.length - fraction)
}
export function scalarKey(node) {
  if (node.type === 'number') return decimalKey(node.json_text)
  if (node.type === 'string') return JSON.parse(node.json_text)
  return node.json_text
}
export function prepareJSONCohort(predicate) {
  if (predicate == null) return null
  need(typeof predicate.pointer === 'string' && predicate.pointer.isWellFormed() && /^(?:\/(?:[^~]|~[01])*)?$/u.test(predicate.pointer) && new TextEncoder().encode(predicate.pointer).length <= 4096, 'Use an exact relative JSON Pointer for the cohort field')
  need(['string', 'number', 'boolean', 'null'].includes(predicate.type), 'Choose a scalar cohort type')
  need(typeof predicate.json_text === 'string' && new TextEncoder().encode(predicate.json_text).length <= 4096, 'Cohort equality value must be at most 4096 UTF-8 bytes')
  const value = parseJSONSource(predicate.json_text).nodes[0]
  need(value.type === predicate.type, 'Enter one JSON scalar matching the chosen type (strings need quotes)')
  return Object.freeze({ pointer: predicate.pointer, type: predicate.type, json_text: predicate.json_text, key: scalarKey(value) })
}
