# browser-render

> To run all at once:
> `node server.ts ../data/*.md --port 8080`

Render Markdown docs (e.g. `../data/programming-languages.md`) as a styled
webpage with working `<abbr>` hover tooltips, a sticky header/first-column, and
horizontal scroll for wide tables.

## Live preview (auto-reloads on edit)

```sh
node server.ts                              # serves ../data/programming-languages.md on :8080
node server.ts path/to/other.md --port 8081 # custom file / port
node server.ts a.md b.md c.md               # several files at once, one server
```

Args are order-independent: `--port N` (or `-p N`, or a bare integer) sets the
port; everything else is a Markdown file to serve. Each file is served at its
own route `/<filename-without-.md>` — e.g. `a.md` → <http://localhost:8080/a>.
With a single file, `/` renders it directly (as before); with several, `/`
lists them.

Open <http://localhost:8080/>. Each page re-renders on every request and the
browser auto-reloads (via Server-Sent Events) whenever *that* file changes. The
reload stream and the on-disk Points-weights sidecar are scoped per document, so
multiple files can be previewed and edited simultaneously without sharing state.

If `node_modules/` is missing (it's gitignored), restore the dependencies:

```sh
npm install markdown-it@14 @types/markdown-it @types/node
```

## Standalone HTML (no server)

`programming-languages.html` is a self-contained, portable snapshot — open it
directly in a browser. Regenerate it after editing the Markdown:

```sh
npx markdown-it ../data/programming-languages.md > /tmp/body.html
cat header.html /tmp/body.html footer.html > programming-languages.html
```

## Files

- `server.ts` — live-reload preview server (Node built-ins + markdown-it)
- `header.html` / `footer.html` — page shell + CSS, and the table-wrap script
- `programming-languages.html` — standalone rendered snapshot
