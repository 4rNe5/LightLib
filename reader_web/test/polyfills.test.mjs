// The functions the reader page fills in where a browser lacks them,
// against the real ones.
import { test } from 'node:test'
import assert from 'node:assert/strict'

const real = {
    objectGroupBy: Object.groupBy, mapGroupBy: Map.groupBy,
    at: Array.prototype.at, stringAt: String.prototype.at,
    findLast: Array.prototype.findLast, findLastIndex: Array.prototype.findLastIndex,
}
delete Object.groupBy
delete Map.groupBy
delete Array.prototype.at
delete String.prototype.at
delete Array.prototype.findLast
delete Array.prototype.findLastIndex
await import('../src/polyfills.js')

test('they were filled in', () => {
    assert.notEqual(Object.groupBy, real.objectGroupBy)
    assert.notEqual(Map.groupBy, real.mapGroupBy)
    assert.notEqual(Array.prototype.at, real.at)
})

test('Object.groupBy, as the EPUB reader uses it', () => {
    const items = [{ ns: 'dc', n: 1 }, { ns: 'opf', n: 2 }, { ns: 'dc', n: 3 }, { ns: undefined, n: 4 }]
    const by = x => x.ns
    assert.deepEqual({ ...Object.groupBy(items, by) }, { ...real.objectGroupBy(items, by) })
    assert.equal(Object.getPrototypeOf(Object.groupBy(items, by)), null)
    // Any iterable (an element's children), with the index.
    const seen = []
    Object.groupBy(new Set(['a', 'b']), (x, i) => (seen.push(i), x))
    assert.deepEqual(seen, [0, 1])
    assert.deepEqual({ ...Object.groupBy([], by) }, {})
})

test('Map.groupBy keeps keys as they are', () => {
    const a = {}, b = {}
    const items = [[a, 1], [b, 2], [a, 3]]
    const mine = Map.groupBy(items, x => x[0]), theirs = real.mapGroupBy(items, x => x[0])
    assert.deepEqual([...mine], [...theirs])
    assert.equal(mine.get(a).length, 2)
})

test('at, findLast, findLastIndex', () => {
    const list = [5, 6, 7]
    for (const i of [0, 1, -1, -3, -4, 3, 1.7, NaN, undefined]) {
        assert.equal(list.at(i), real.at.call(list, i), `at(${i})`)
        assert.equal('abc'.at(i), real.stringAt.call('abc', i), `string at(${i})`)
    }
    const even = x => x % 2 === 0
    assert.equal(list.findLast(even), real.findLast.call(list, even))
    assert.equal(list.findLastIndex(even), real.findLastIndex.call(list, even))
    assert.equal([1, 3].findLastIndex(even), -1)
    assert.equal([1, 3].findLast(even), undefined)
})
