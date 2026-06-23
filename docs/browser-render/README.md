# browser-render

Render Markdown docs (e.g. `../research/programming-languages.md`) as a styled
webpage with working `<abbr>` hover tooltips, a sticky header/first-column, and
horizontal scroll for wide tables.

## Live preview (auto-reloads on edit)

```sh
node server.js                       # serves ../research/programming-languages.md
node server.js path/to/other.md 8081 # custom file / port
```

Open <http://localhost:8080/>. The page re-renders on every request and the
browser auto-reloads (via Server-Sent Events) whenever the watched file changes.

If `node_modules/` is missing (it's gitignored), restore the one dependency:

```sh
npm install markdown-it@14
```

## Standalone HTML (no server)

`programming-languages.html` is a self-contained, portable snapshot — open it
directly in a browser. Regenerate it after editing the Markdown:

```sh
npx markdown-it ../research/programming-languages.md > /tmp/body.html
cat header.html /tmp/body.html footer.html > programming-languages.html
```

## Files

- `server.js` — live-reload preview server (Node built-ins + markdown-it)
- `header.html` / `footer.html` — page shell + CSS, and the table-wrap script
- `programming-languages.html` — standalone rendered snapshot
