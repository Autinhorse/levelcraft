import { defineConfig } from 'vite';

// Phase 1: single entry (game). The level editor will be added as a second
// entry point in a later phase, at which point this config grows
// `build.rollupOptions.input` to a record { main, editor }.
export default defineConfig({
  build: {
    target: 'es2022',
    sourcemap: true,
  },
  server: {
    port: 5173,
    open: false,
  },
});
