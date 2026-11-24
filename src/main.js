import 'katex/dist/katex.min.css'
import { renderMarkdown } from './markdown.js'
import sample from './sample.md?raw'

const STORE_KEY = 'mdtex:last'
const SCROLL_KEY = 'mdtex:scroll'

// Inside the Mac app the page is served over mdtex://, and local files are
// readable at /__file__/<absolute path>.
const isApp = location.protocol === 'mdtex:'
if (isApp) {
  document.documentElement.classList.add('app')
  document.documentElement.classList.toggle('sans-serif', window.mdtexSansSerif === true)
}

const doc = document.getElementById('doc')
if (isApp) {
  let findModule
  let findSession = 0
  window.mdtexFind = async options => {
    if (options.action === 'dismiss') {
      findSession++
      findModule?.clearFindHighlights()
      return
    }
    const session = findSession
    findModule ??= await import('./find.js')
    if (session === findSession) return findModule.findInDocument(doc, options)
  }
}
const nameEl = document.getElementById('name')
const fileInput = document.getElementById('file')
const openBtn = document.getElementById('open')
const drop = document.getElementById('drop')

const encodePath = (p) => p.split('/').map(encodeURIComponent).join('/')

function showDocument(html, name, baseDir) {
  // Resolve local image paths and finish formatting before WebKit lays out the page.
  const template = document.createElement('template')
  template.innerHTML = html
  const content = template.content

  // A leading top-level heading is treated like \maketitle.
  const first = content.firstElementChild
  if (first && first.tagName === 'H1') first.classList.add('title')

  // Wide tables scroll inside themselves instead of stretching the page.
  for (const table of content.querySelectorAll('table')) {
    const wrap = document.createElement('div')
    wrap.className = 'table-wrap'
    table.replaceWith(wrap)
    wrap.append(table)
  }

  // Images with relative paths are loaded from the folder the document is in.
  if (baseDir != null) {
    const base = `${location.origin}/__file__${encodePath(baseDir)}/`
    for (const img of content.querySelectorAll('img[src]')) {
      const src = img.getAttribute('src')
      if (/^([a-z][a-z0-9+.-]*:|\/\/)/i.test(src)) continue
      try {
        img.src = src.startsWith('/') ? `${location.origin}/__file__${src}` : new URL(src, base).href
      } catch {
        // Leave an unparseable path as it is.
      }
    }
  }

  // A paragraph holding only an image is set as a centred figure.
  for (const img of content.querySelectorAll('p > img:only-child')) {
    const p = img.parentElement
    if (p.textContent.trim() !== '') continue
    p.classList.add('figure')
    if (img.title) {
      const cap = document.createElement('span')
      cap.className = 'caption'
      cap.textContent = img.title
      p.append(cap)
    }
  }

  for (const a of content.querySelectorAll('a[href]')) {
    if (!a.getAttribute('href').startsWith('#')) {
      a.target = '_blank'
      a.rel = 'noreferrer'
    }
  }

  doc.replaceChildren(content)
  nameEl.textContent = name || ''
  document.title = name ? `${name} · mdtex` : 'mdtex'
  window.scrollTo(0, 0)
  if (isApp) {
    window.webkit?.messageHandlers?.documentRendered?.postMessage({ name: name || '', fromPath: baseDir != null })
  }
}

// Loading a parser or reading a file can finish after a more recent open.
let documentRequest = 0

async function openFile(file) {
  if (!file) return
  const request = ++documentRequest
  const text = await file.text()
  const html = await renderMarkdown(text)
  if (request !== documentRequest) return
  showDocument(html, file.name)
  if (isApp) return
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify({ name: file.name, text }))
  } catch {
    // Too large to remember, or storage is unavailable; the document still shows.
  }
}

openBtn.addEventListener('click', () => fileInput.click())
fileInput.addEventListener('change', () => {
  openFile(fileInput.files[0])
  fileInput.value = ''
})

if (!isApp) {
  window.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'o') {
      e.preventDefault()
      fileInput.click()
    }
  })
}

// Drag and drop anywhere on the page.
let dragDepth = 0
const hasFiles = (e) => !isApp && e.dataTransfer && [...e.dataTransfer.types].includes('Files')

window.addEventListener('dragenter', (e) => {
  if (!hasFiles(e)) return
  e.preventDefault()
  dragDepth++
  drop.classList.add('on')
})
window.addEventListener('dragover', (e) => {
  if (hasFiles(e)) e.preventDefault()
})
window.addEventListener('dragleave', (e) => {
  if (!hasFiles(e)) return
  dragDepth = Math.max(0, dragDepth - 1)
  if (dragDepth === 0) drop.classList.remove('on')
})
window.addEventListener('drop', (e) => {
  if (!hasFiles(e)) return
  e.preventDefault()
  dragDepth = 0
  drop.classList.remove('on')
  openFile(e.dataTransfer.files[0])
})

// ── What to show first ──

const filePath = new URLSearchParams(location.search).get('file')

async function readPath(path) {
  const res = await fetch(`/__file__${encodePath(path)}`, { cache: 'no-store' })
  if (!res.ok) throw new Error(String(res.status))
  return res.text()
}

async function openPath(path) {
  const request = ++documentRequest
  const slash = path.lastIndexOf('/')
  const name = path.slice(slash + 1)
  try {
    const embeddedSource = document.getElementById('initial-source')
    const text = embeddedSource ? JSON.parse(embeddedSource.textContent) : await readPath(path)
    embeddedSource?.remove()
    const html = await renderMarkdown(text)
    if (request !== documentRequest) return
    showDocument(html, name, path.slice(0, slash))
  } catch {
    const html = await renderMarkdown(`# File not found\n\nThe file \`${path}\` could not be read.`)
    if (request === documentRequest) showDocument(html, name)
    return
  }
  // A reload (after the file was edited) returns to the same place.
  try {
    const y = Number(sessionStorage.getItem(SCROLL_KEY))
    if (y > 0) window.scrollTo(0, y)
    window.addEventListener('pagehide', () => sessionStorage.setItem(SCROLL_KEY, String(window.scrollY)))
  } catch {
    // No session storage; the document just starts at the top.
  }
}

async function restorePreview(last) {
  const request = ++documentRequest
  const hasSavedDocument = typeof last?.text === 'string'
  const html = await renderMarkdown(hasSavedDocument ? last.text : sample)
  if (request === documentRequest) showDocument(html, hasSavedDocument ? last.name : '')
}

if (filePath) {
  openPath(filePath)
} else {
  let last = null
  if (!isApp) {
    try {
      last = JSON.parse(localStorage.getItem(STORE_KEY))
    } catch {
      last = null
    }
  }
  restorePreview(last)
}
