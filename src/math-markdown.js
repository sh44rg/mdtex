import { katex } from '@mdit/plugin-katex'

// Parse math with Markdown so code spans and fenced code stay literal.
export function addMath(markdown) {
  return markdown.use(katex, {
    delimiters: 'all', // $…$, $$…$$, \(…\), and \[…\]
    mathFence: true,
    throwOnError: false, // a malformed formula must not hide the rest of the file
    trust: false,
    maxSize: 20,
    maxExpand: 1000,
  })
}
