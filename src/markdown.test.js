import assert from 'node:assert/strict'
import test from 'node:test'
import { renderMarkdown } from './markdown.js'

test('renders plain Markdown with typography and linkification', async () => {
  const html = await renderMarkdown('# Title\n\n"See **this**" -- https://example.com')
  assert.match(html, /^<h1>Title<\/h1>/)
  assert.match(html, /“See <strong>this<\/strong>” – /)
  assert.match(html, /<a href="https:\/\/example\.com">https:\/\/example\.com<\/a>/)
})

test('renders the hypothesis list with subscripts and decimal probabilities', async () => {
  const html = await renderMarkdown('- $h_1$: all cherry, with prior probability $0.1$.')
  assert.match(html, /<li>/)
  assert.match(html, /<msub><mi>h<\/mi><mn>1<\/mn><\/msub>/)
  assert.match(html, /<mn>0\.1<\/mn>/)
  assert.doesNotMatch(html, /\$/)
})

test('supports both inline delimiters and display delimiters', async () => {
  for (const source of [String.raw`$x^2$`, String.raw`\(x^2\)`]) {
    const html = await renderMarkdown(source)
    assert.match(html, /class="katex"/)
    assert.doesNotMatch(html, /class="katex-display"/)
  }
  for (const source of [
    '$$\n\\frac{1}{2}\n$$',
    String.raw`\[\frac{1}{2}\]`,
    '```math\n\\frac{1}{2}\n```',
    '~~~ math\n\\frac{1}{2}\n~~~',
  ]) {
    const html = await renderMarkdown(source)
    assert.match(html, /class="katex-display"/)
    assert.match(html, /<mfrac>/)
  }
})

test('keeps code, escaped dollars, and ordinary prices literal', async () => {
  const html = await renderMarkdown('`$h_1$`\n\n```tex\n$h_1$\n```\n\n\\$5 and $10 to $20.\n\nUnclosed $x')
  assert.doesNotMatch(html, /class="katex"/)
  assert.match(html, /<code>\$h_1\$<\/code>/)
  assert.match(html, /\$5 and \$10 to \$20/)
  assert.match(html, /Unclosed \$x/)
})

test('a malformed formula does not prevent subsequent content rendering', async () => {
  const html = await renderMarkdown(String.raw`$\frac{1}{$` + '\n\nStill readable: $x^2$.')
  assert.match(html, /katex-error/)
  assert.match(html, /Still readable:/)
  assert.match(html, /<msup>/)
})

test('formulae cannot enable HTML or trusted commands', async () => {
  const html = await renderMarkdown(String.raw`<script>alert(1)</script>

$\href{javascript:alert(1)}{click}$

$\includegraphics{https://example.com/image.png}$`)
  assert.doesNotMatch(html, /<script|<a\b|<img\b/)
  assert.match(html, /&lt;script&gt;/)
})
