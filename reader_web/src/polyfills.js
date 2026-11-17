// What foliate-js uses that browsers a few years old do not have (the
// build's target is Chrome 90 / Safari 15, but a bundler only rewrites
// syntax - a missing function stays missing). A book did not open in
// Chrome 112: "Object.groupBy is not a function" (it came with 117).

const define = (target, name, value) => {
    if (typeof target[name] !== 'function') {
        Object.defineProperty(target, name, { value, writable: true, configurable: true })
    }
}

// Chrome 117, Safari 17.4.
define(Object, 'groupBy', (items, keyOf) => {
    const groups = Object.create(null)
    let index = 0
    for (const item of items) {
        const key = keyOf(item, index++)
        const k = typeof key === 'symbol' ? key : `${key}`
        ;(groups[k] ??= []).push(item)
    }
    return groups
})
define(Map, 'groupBy', (items, keyOf) => {
    const groups = new Map()
    let index = 0
    for (const item of items) {
        const key = keyOf(item, index++)
        const group = groups.get(key)
        if (group) group.push(item)
        else groups.set(key, [item])
    }
    return groups
})

// Chrome 92, Safari 15.4.
function at(index) {
    const n = Math.trunc(index) || 0
    const i = n < 0 ? this.length + n : n
    return i < 0 || i >= this.length ? undefined : this[i]
}
define(Array.prototype, 'at', at)
define(String.prototype, 'at', at)

// Chrome 97, Safari 15.4.
define(Array.prototype, 'findLastIndex', function (test, thisArg) {
    for (let i = this.length - 1; i >= 0; i--) {
        if (test.call(thisArg, this[i], i, this)) return i
    }
    return -1
})
define(Array.prototype, 'findLast', function (test, thisArg) {
    for (let i = this.length - 1; i >= 0; i--) {
        if (test.call(thisArg, this[i], i, this)) return this[i]
    }
    return undefined
})
