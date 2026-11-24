const blockTags = new Set([
  'BLOCKQUOTE', 'DIV', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HR',
  'LI', 'OL', 'P', 'PRE', 'TABLE', 'TD', 'TH', 'TR', 'UL',
])
const wordSegmenter = new Intl.Segmenter(undefined, { granularity: 'word' })
const graphemes = new Intl.Segmenter()
const allHighlight = 'mdtex-find'
const activeHighlight = 'mdtex-find-current'
const startsWithMark = /^\p{M}/u
let search

function findRanges(doc, { query, matchCase, matchDiacritics, wholeWords }) {
  const normalize = text => {
    text = text.replace(/\s+/gu, ' ')
    if (!matchDiacritics) text = text.normalize('NFD').replace(/\p{M}/gu, '')
    return text.normalize('NFC')
  }
  const pattern = normalize(query).trim()
  if (!pattern) return []
  const escaped = pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const expression = new RegExp(escaped, matchCase ? 'gu' : 'giu')
  const ranges = []
  let parts = []
  let source = ''

  function append(node, text) {
    if (!text) return
    parts.push({ node, start: source.length, end: source.length + text.length })
    source += text
  }

  function flush() {
    if (!source) return
    const text = normalize(source)
    // Text offsets can change when whitespace collapses or combining marks are removed.
    const starts = []
    const ends = []
    if (source !== text && (source.length !== text.length || /[^\x00-\x7f]/.test(source))) {
      let previousWasSpace = false
      for (const { segment, index } of graphemes.segment(source)) {
        const folded = normalize(segment)
        if (!folded) continue
        const space = folded === ' '
        if (space && previousWasSpace) {
          ends[ends.length - 1] = index + segment.length
        } else {
          for (let i = 0; i < folded.length; i++) {
            starts.push(index)
            ends.push(index + segment.length)
          }
        }
        previousWasSpace = space
      }
    }
    const wordStarts = new Set()
    const wordEnds = new Set()
    if (wholeWords) {
      for (const part of wordSegmenter.segment(text)) {
        wordStarts.add(part.index)
        wordEnds.add(part.index + part.segment.length)
      }
    }
    for (const match of text.matchAll(expression)) {
      const start = match.index
      const end = start + match[0].length
      if (matchDiacritics && startsWithMark.test(text.slice(end, end + 2))) continue
      if (wholeWords && (!wordStarts.has(start) || !wordEnds.has(end))) continue
      const startOffset = starts[start] ?? start
      const endOffset = ends[end - 1] ?? end
      const first = parts.find(part => part.end > startOffset)
      const last = parts.find(part => part.end >= endOffset)
      if (!first?.node || !last?.node) continue
      const range = document.createRange()
      range.setStart(first.node, startOffset - first.start)
      range.setEnd(last.node, endOffset - last.start)
      ranges.push(range)
    }
    source = ''
    parts = []
  }

  function visit(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      append(node, node.data)
      return
    }
    if (node.nodeType !== Node.ELEMENT_NODE || node.matches('[hidden], .katex-mathml')) return
    if (node.tagName === 'BR') {
      append(null, ' ')
      return
    }
    const separatesText = blockTags.has(node.tagName)
    if (separatesText) flush()
    for (const child of node.childNodes) visit(child)
    if (separatesText) flush()
  }

  visit(doc)
  flush()
  return ranges
}

function reveal(range) {
  const scrollBox = range.startContainer.parentElement.closest('pre, .table-wrap, .katex-display')
  if (scrollBox) {
    const match = range.getClientRects()[0]
    const box = scrollBox.getBoundingClientRect()
    if (match && (match.left < box.left || match.right > box.right)) {
      scrollBox.scrollLeft += match.left - box.left - 12
    }
  }
  const match = range.getClientRects()[0]
  if (match && (match.top < 12 || match.bottom > window.innerHeight - 12)) {
    window.scrollBy(0, match.top - window.innerHeight / 2)
  }
}

export function clearFindHighlights() {
  const highlights = CSS.highlights
  if (highlights) {
    for (const name of [activeHighlight, allHighlight]) {
      highlights.get(name)?.clear()
      highlights.delete(name)
    }
  } else if (search?.ranges.length) {
    window.getSelection()?.removeAllRanges()
  }
}

export function findInDocument(doc, options) {
  const { action, query, matchCase, matchDiacritics, wholeWords, highlightAll } = options
  const highlights = CSS.highlights
  if (!query) {
    clearFindHighlights()
    search = undefined
    return { current: 0, total: 0, supportsHighlightAll: !!highlights }
  }

  highlights?.delete(activeHighlight)
  const key = JSON.stringify([query, matchCase, matchDiacritics, wholeWords])
  const sameSearch = search?.firstChild === doc.firstChild && search.key === key
  if (!sameSearch) {
    const ranges = findRanges(doc, options)
    search = { firstChild: doc.firstChild, key, ranges, index: action === 'previous' ? ranges.length - 1 : 0 }
  }
  const { ranges } = search
  if (!sameSearch || !highlightAll) highlights?.delete(allHighlight)
  if (!ranges.length) {
    if (!highlights) window.getSelection()?.removeAllRanges()
    return { current: 0, total: 0, supportsHighlightAll: !!highlights }
  }
  if (sameSearch && action === 'next') search.index = (search.index + 1) % ranges.length
  if (sameSearch && action === 'previous') search.index = (search.index + ranges.length - 1) % ranges.length

  const current = ranges[search.index]
  if (highlights) {
    if (highlightAll && !highlights.has(allHighlight)) {
      const all = new Highlight()
      for (const range of ranges) all.add(range)
      highlights.set(allHighlight, all)
    }
    const active = new Highlight(current)
    active.priority = 1
    highlights.set(activeHighlight, active)
  } else {
    const selection = window.getSelection()
    selection?.removeAllRanges()
    selection?.addRange(current)
  }
  if (action !== 'highlight') reveal(current)
  return { current: search.index + 1, total: ranges.length, supportsHighlightAll: !!highlights }
}
