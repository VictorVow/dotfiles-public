const http = require('http');
const fs = require('fs');
const path = require('path');

// Live Markdown preview server.
//   node server.js [--port N] [file1.md file2.md ...]
// Renders each Markdown file on every request and pushes a browser reload (via
// SSE) whenever that file changes. Multiple files can be served at once, each
// at its own route (/<docKey>), so they can be previewed + edited side by side.
// Templates and the markdown-it dependency live alongside this script, so it
// can run from anywhere.
//
// Args (order-independent):
//   --port N | -p N | a bare integer   -> listen port (default 8080)
//   anything else                      -> a Markdown file to serve
// With no files given, defaults to ../research/programming-languages.md.

function parseArgs(argv) {
  const files = [];
  let port = 8080;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--port' || a === '-p') {
      port = Number(argv[++i]) || port;
    } else if (a.startsWith('--port=')) {
      port = Number(a.slice('--port='.length)) || port;
    } else if (/^\d+$/.test(a)) {
      // Bare integer -> port (keeps the old `server.js file.md 8081` form working).
      port = Number(a);
    } else {
      files.push(a);
    }
  }
  if (files.length === 0) {
    files.push(path.join(__dirname, '..', 'research', 'programming-languages.md'));
  }
  return { files, port };
}

const { files, port: PORT } = parseArgs(process.argv.slice(2));
const HEADER = path.join(__dirname, 'header.html');
const FOOTER = path.join(__dirname, 'footer.html');

// Build one descriptor per served document. docKey (the source filename without
// extension) is the stable per-document identifier: it routes requests, scopes
// SSE reloads + weights, and is injected into the page so the browser can
// namespace its localStorage (Compare selection, Points weights cache) per doc.
const docs = new Map();   // docKey -> descriptor
const byFile = new Map(); // `${dir}\0${base}` -> docKey, for the change watcher
for (const f of files) {
  const mdPath = path.resolve(f);
  const dir = path.dirname(mdPath);
  const base = path.basename(mdPath);
  const docKey = base.replace(/\.md$/, '');
  if (docs.has(docKey)) {
    console.warn('skipping duplicate doc key: ' + docKey + ' (' + mdPath + ')');
    continue;
  }
  docs.set(docKey, {
    key: docKey,
    md: mdPath,
    dir,
    base,
    // Sidecar for browser-set Points weights, alongside the source .md. Named so
    // it does NOT match base, so writing it never trips the reload watcher.
    weights: path.join(dir, docKey + '.weights.json'),
    clients: new Set(),
  });
  byFile.set(dir + '\0' + base, docKey);
}

const MarkdownIt = require(path.join(__dirname, 'node_modules', 'markdown-it'));
const md = new MarkdownIt({ html: true, linkify: true });

function liveReload(docKey) {
  return `
<script>
  (function () {
    var es = new EventSource('/events?doc=${encodeURIComponent(docKey)}');
    es.onmessage = function () { location.reload(); };
    es.onerror = function () { /* server restart: keep retrying */ };
  })();
</script>
`;
}

function render(doc) {
  const header = fs.readFileSync(HEADER, 'utf8');
  const footer = fs.readFileSync(FOOTER, 'utf8');
  const body = md.render(fs.readFileSync(doc.md, 'utf8'));
  const weightsUrl = '/weights?doc=' + encodeURIComponent(doc.key);
  const docGlobal =
    `<script>window.PL_DOC_KEY = ${JSON.stringify(doc.key)};` +
    `window.PL_WEIGHTS_URL = ${JSON.stringify(weightsUrl)};</script>\n`;
  return header + docGlobal + body + liveReload(doc.key) + footer;
}

function renderIndex() {
  const items = [...docs.values()]
    .map((d) => `<li><a href="/${encodeURIComponent(d.key)}">${d.key}</a> ` +
      `<small>(${d.md})</small></li>`)
    .join('\n');
  return '<!doctype html><meta charset="utf-8"><title>Markdown preview</title>' +
    '<style>body{font:16px system-ui,sans-serif;max-width:46rem;margin:3rem auto;padding:0 1rem}' +
    'li{margin:.4rem 0}small{color:#888}</style>' +
    '<h1>Markdown preview</h1><ul>\n' + items + '\n</ul>';
}

function send(res, code, type, payload) {
  res.writeHead(code, { 'Content-Type': type });
  res.end(payload);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const pathname = decodeURIComponent(url.pathname);
  const docKey = url.searchParams.get('doc');

  if (pathname === '/events') {
    const doc = docs.get(docKey);
    if (!doc) { res.writeHead(404); res.end('unknown doc'); return; }
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    });
    res.write('retry: 1000\n\n');
    doc.clients.add(res);
    req.on('close', () => doc.clients.delete(res));
    return;
  }

  if (pathname === '/weights') {
    const doc = docs.get(docKey);
    if (!doc) { res.writeHead(404); res.end('unknown doc'); return; }
    // Persist the browser's Points weights to disk (and read them back).
    if (req.method === 'GET') {
      fs.readFile(doc.weights, 'utf8', (err, data) => {
        send(res, 200, 'application/json', err ? '{}' : data);
      });
      return;
    }
    if (req.method === 'POST') {
      let body = '';
      req.on('data', (chunk) => {
        body += chunk;
        if (body.length > 1e6) req.destroy(); // guard against runaway payloads
      });
      req.on('end', () => {
        let parsed;
        try { parsed = JSON.parse(body); }
        catch (e) { res.writeHead(400); res.end('invalid JSON'); return; }
        fs.writeFile(doc.weights, JSON.stringify(parsed, null, 2) + '\n', (err) => {
          if (err) { res.writeHead(500); res.end('write error'); return; }
          res.writeHead(204);
          res.end();
        });
      });
      return;
    }
    res.writeHead(405);
    res.end('method not allowed');
    return;
  }

  // Root: render the single doc directly (old behavior) or list all docs.
  if (pathname === '/' || pathname.startsWith('/index')) {
    if (docs.size === 1) {
      const only = docs.values().next().value;
      try {
        send(res, 200, 'text/html; charset=utf-8', render(only));
      } catch (e) {
        send(res, 500, 'text/plain', 'Render error:\n' + e.stack);
      }
      return;
    }
    send(res, 200, 'text/html; charset=utf-8', renderIndex());
    return;
  }

  // /<docKey> -> render that document.
  const key = pathname.replace(/^\/+/, '').replace(/\/+$/, '');
  const doc = docs.get(key);
  if (doc) {
    try {
      send(res, 200, 'text/html; charset=utf-8', render(doc));
    } catch (e) {
      send(res, 500, 'text/plain', 'Render error:\n' + e.stack);
    }
    return;
  }

  res.writeHead(404);
  res.end('not found');
});

// Watch each directory containing a served file; on change, reload only the
// clients viewing the doc whose source file changed.
const timers = new Map();
for (const dir of new Set([...docs.values()].map((d) => d.dir))) {
  fs.watch(dir, (ev, file) => {
    const key = byFile.get(dir + '\0' + file);
    if (!key) return;
    clearTimeout(timers.get(key));
    timers.set(key, setTimeout(() => {
      const doc = docs.get(key);
      console.log('change detected -> reloading ' + doc.clients.size +
        ' client(s) for ' + key);
      for (const res of doc.clients) res.write('data: reload\n\n');
    }, 120));
  });
}

server.listen(PORT, () => {
  console.log('Live preview on http://localhost:' + PORT + '/');
  for (const d of docs.values()) {
    console.log('  /' + d.key + '  <-  ' + d.md + '  (weights: ' + d.weights + ')');
  }
});
