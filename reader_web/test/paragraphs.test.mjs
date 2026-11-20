// The reader's paragraphs (reader_web/src/paragraphs.js) read as the app
// reads them (paragraph_text.dart; test/reader_paragraphs_test.dart has
// the same lines): `npm test`. Elements here are stand-ins with just what
// the code asks of one.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { glyphOf, hasIllustration, textOf } from '../src/paragraphs.js'

const text = data => ({ nodeType: 3, data })
function el(tag, attrs = {}, ...children) {
    const all = () => children.flatMap(c => c.nodeType === 1 ? [c, ...c.all()] : [])
    return {
        nodeType: 1, tagName: tag, childNodes: children, all,
        getAttribute: name => attrs[name] ?? null,
        querySelector: sel => all().find(c => sel.split(/,\s*/).includes(c.tagName)) ?? null,
        querySelectorAll: sel => all().filter(c => sel.split(/,\s*/).includes(c.tagName)),
    }
}
const img = attrs => el('img', attrs)

test('a glyph set as a picture: what it stands for', () => {
    assert.equal(glyphOf(img({ class: 'gaiji', alt: '!!?' })), '!!?')
    assert.equal(glyphOf(img({ class: 'gaiji', alt: '葛' })), '葛')
    assert.equal(glyphOf(img({ class: 'x gaiji-wide', alt: '' })), '')
    assert.equal(glyphOf(img({ class: 'gaiji-line', alt: 'ア濁点' })), 'ア゙')
    assert.equal(glyphOf(img({ class: 'gaiji', alt: 'パ半濁点' })), 'パ゚')
    assert.equal(glyphOf(img({ class: 'gaiji', alt: '外字の説明' })), '')
    assert.equal(glyphOf(img({ alt: '♡' })), '♡')
    // What an illustration is called is not a glyph, one letter or not.
    assert.equal(glyphOf(img({ alt: '絵' })), null)
    assert.equal(glyphOf(img({ src: 'a.jpg', alt: '1' })), null)
    assert.equal(glyphOf(img({ src: 'a.jpg' })), null)
})

test('a line with such a glyph is text, read with it; an illustration is not', () => {
    const line = el('p', {}, text('「それでいいのかな'), img({ class: 'gaiji', alt: '!!?' }), text('」'))
    assert.equal(hasIllustration(line), false)
    assert.equal(textOf(line), '「それでいいのかな!!?」')
    const word = el('p', {}, text('魔法'), img({ class: 'gaiji', alt: '杖' }), text('の職人だ。'))
    assert.equal(textOf(word), '魔法杖の職人だ。')
    const inSpan = el('p', {}, text('なんだって'), el('span', {}, img({ alt: '!?' })))
    assert.equal(hasIllustration(inSpan), false)
    assert.equal(textOf(inSpan), 'なんだって!?')

    assert.equal(hasIllustration(el('p', {}, img({ src: 'i-001.jpg', alt: '' }))), true)
    assert.equal(hasIllustration(el('div', {}, img({ src: 'i-002.jpg', alt: '絵' }), text('挿絵の説明'))), true)
    assert.equal(hasIllustration(el('p', {}, text('次の'), img({ class: 'gaiji', alt: '杖' }), el('svg'))), true)
})
