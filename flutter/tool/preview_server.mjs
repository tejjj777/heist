import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { resolve, sep } from 'node:path';
const root = resolve('build/web');
const prefix = '/heist/';
const mime = {'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.css':'text/css','.png':'image/png','.ttf':'font/ttf','.woff2':'font/woff2','.svg':'image/svg+xml'};
http.createServer(async (request, response) => {
  try {
    const path = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    if (path === '/' || path === '/heist') { response.writeHead(302, {Location:prefix}); response.end(); return; }
    if (!path.startsWith(prefix)) { response.writeHead(404); response.end(); return; }
    const file = resolve(root, path.slice(prefix.length) || 'index.html');
    if (file !== root && !file.startsWith(root + sep)) { response.writeHead(403); response.end(); return; }
    if (!(await stat(file)).isFile()) throw Error('not a file');
    const type = Object.entries(mime).find(([ext]) => file.endsWith(ext))?.[1] ?? 'application/octet-stream';
    response.writeHead(200, {'Content-Type':type,'Cache-Control':'no-cache'});
    response.end(await readFile(file));
  } catch { response.writeHead(404); response.end('Not found'); }
}).listen(8765, '127.0.0.1', () => console.log('HEIST Flutter preview: http://127.0.0.1:8765/heist/'));
