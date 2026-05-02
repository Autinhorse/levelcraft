import { defineConfig, type Plugin } from 'vite';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Dev-only middleware that lets the in-browser editor save level
// changes back to disk. POST /api/save-level with body
//     { path: "levels/level-NN.json", level: { ... } }
// → writes public/levels/level-NN.json. The path is whitelisted so
// only the 12 numbered slots can be overwritten — no escape into the
// rest of the project.
//
// Production builds have no Vite server, so the editor's Save button
// will fail with a network error there. That's expected for now: real
// saves will go through a backend API once there is one.
const levelSavePlugin: Plugin = {
  name: 'level-save',
  configureServer(server) {
    server.middlewares.use('/api/save-level', (req, res, next) => {
      if (req.method !== 'POST') {
        next();
        return;
      }
      let body = '';
      req.on('data', (chunk: Buffer) => {
        body += chunk.toString();
      });
      req.on('end', () => {
        try {
          const parsed = JSON.parse(body) as { path?: string; level?: unknown };
          const targetPath = parsed.path;
          const level = parsed.level;
          // Whitelist: levels/level-NN.json with NN as 2-digit number.
          if (!targetPath || !/^levels\/level-\d{2}\.json$/.test(targetPath)) {
            res.statusCode = 400;
            res.setHeader('content-type', 'application/json');
            res.end(JSON.stringify({ error: `invalid path: ${targetPath ?? '(missing)'}` }));
            return;
          }
          if (!level || typeof level !== 'object') {
            res.statusCode = 400;
            res.setHeader('content-type', 'application/json');
            res.end(JSON.stringify({ error: 'invalid level body' }));
            return;
          }
          const filePath = resolve(process.cwd(), 'public', targetPath);
          writeFileSync(filePath, JSON.stringify(level, null, 2) + '\n');
          res.statusCode = 200;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ ok: true }));
        } catch (err) {
          res.statusCode = 500;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: (err as Error).message }));
        }
      });
    });
  },
};

// Phase 1: single entry (game). The level editor will be added as a second
// entry point in a later phase, at which point this config grows
// `build.rollupOptions.input` to a record { main, editor }.
export default defineConfig({
  plugins: [levelSavePlugin],
  build: {
    target: 'es2022',
    sourcemap: true,
  },
  server: {
    // host: true binds to all interfaces (0.0.0.0 + ::), avoiding the
    // localhost-IPv4-vs-IPv6 ambiguity that bites on Windows where Chrome/
    // Edge try IPv4 first but Vite may bind IPv6 only.
    host: true,
    port: 5173,
    strictPort: false, // auto-bump to next free port if 5173 is taken
    open: true,        // pop the browser on first start
  },
});
