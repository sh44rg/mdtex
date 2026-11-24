import MarkdownIt from 'markdown-it'

export function createMarkdown() {
  return new MarkdownIt({
    html: false, // raw HTML in a file is shown as text, never executed
    linkify: true,
    typographer: true,
  })
}

// This only rules out documents that cannot contain math. The plugin still
// decides what is math, including when delimiters occur in code or prices.
const possibleMath = /\$|\\[([]|(?:`{3,}|~{3,})\s*math\b/
let plainMarkdown
let mathMarkdown

export async function renderMarkdown(source) {
  if (possibleMath.test(source)) {
    const { addMath } = await import('./math-markdown.js')
    return (mathMarkdown ??= addMath(createMarkdown())).render(source)
  }
  return (plainMarkdown ??= createMarkdown()).render(source)
}
