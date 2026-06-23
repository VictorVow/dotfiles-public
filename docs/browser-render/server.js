const http = require('http');
const fs = require('fs');
const path = require('path');

// Live Markdown preview server.
//   node server.js [path/to/file.md] [port]
// Renders the Markdown on every request and pushes a browser reload (via SSE)
// whenever the file changes. Templates and the markdown-it dependency live
// alongside this script, so it can run from anywhere.

const MD = path.resolve(process.argv[2] || path.join(__dirname, '..', 'research', 'programming-languages.md'));
const PORT = Number(process.argv[3]) || 8080;
const HEADER = path.join(__dirname, 'header.html');
const FOOTER = path.join(__dirname, 'footer.html');
// Sidecar for browser-set Points weights, alongside the source .md. Named so it
// does NOT match basename(MD), so writing it never trips the reload watcher.
const WEIGHTS = path.join(path.dirname(MD), path.basename(MD).replace(/\.md$/, '') + '.weights.json');

const MarkdownIt = require(path.join(__dirname, 'node_modules', 'markdown-it'));
const md = new MarkdownIt({ html: true, linkify: true });

const LIVE_RELOAD = `
<script>
  (function () {
    var es = new EventSource('/events');
    es.onmessage = function () { location.reload(); };
    es.onerror = function () { /* server restart: keep retrying */ };
  })();
</script>
`;

const clients = new Set();

function render() {
  const header = fs.readFileSync(HEADER, 'utf8');
  const footer = fs.readFileSync(FOOTER, 'utf8');
  const body = md.render(fs.readFileSync(MD, 'utf8'));
  return header + body + LIVE_RELOAD + footer;
}

const server = http.createServer((req, res) => {
  if (req.url === '/events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    });
    res.write('retry: 1000\n\n');
    clients.add(res);
    req.on('close', () => clients.delete(res));
    return;
  }
  if (req.url === '/weights') {
    // Persist the browser's Points weights to disk (and read them back).
    if (req.method === 'GET') {
      fs.readFile(WEIGHTS, 'utf8', (err, data) => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(err ? '{}' : data);
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
        fs.writeFile(WEIGHTS, JSON.stringify(parsed, null, 2) + '\n', (err) => {
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
  if (req.url === '/' || req.url.startsWith('/index')) {
    try {
      const html = render();
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('Render error:\n' + e.stack);
    }
    return;
  }
  res.writeHead(404);
  res.end('not found');
});

let timer = null;
fs.watch(path.dirname(MD), (ev, file) => {
  if (file !== path.basename(MD)) return;
  clearTimeout(timer);
  timer = setTimeout(() => {
    console.log('change detected -> reloading ' + clients.size + ' client(s)');
    for (const res of clients) res.write('data: reload\n\n');
  }, 120);
});

server.listen(PORT, () => {
  console.log('Live preview on http://localhost:' + PORT + '/');
  console.log('Watching ' + MD);
  console.log('Weights persisted to ' + WEIGHTS);
});
