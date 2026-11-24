# mdtex

A Markdown viewer that renders documents with the look of a LaTeX PDF: Latin Modern type, a narrow justified column, hyphenation, indented paragraphs, and KaTeX math. Available as a web page (Vite) and as a native macOS app (Swift + WKWebView) for Apple silicon.

## Web

```sh
npm install
npm run dev     # open a .md file with ⌘O or drag it onto the page
npm test
npm run build
```

## macOS app

```sh
./build-app.sh --install   # build and install to /Applications
./build-release.sh         # build a shareable .dmg (see DISTRIBUTION.md)
```

Requires Xcode command-line tools and Node.js. The app targets macOS 13+ on Apple silicon.

## Credits

Built with [Claude Code](https://claude.com/claude-code). Uses markdown-it, KaTeX, latex.css and the Inter font (see `src/fonts/INTER-LICENSE.txt`).
