import { defineConfig } from 'vite';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

export default defineConfig({
  plugins: [
    nodePolyfills({
      // Include Buffer, process, etc.
      include: ['buffer', 'process', 'stream', 'crypto'],
      globals: {
        Buffer: true,
        global: true,
        process: true,
      },
    }),
  ],
  build: {
    lib: {
      entry: './turbo-sdk-entry.js',
      name: 'TurboSDK',
      fileName: () => 'turbo-sdk.bundle.min.js',
      formats: ['es'],
    },
    outDir: '..',
    emptyOutDir: false,
    minify: 'terser',
    sourcemap: false,
    rollupOptions: {
      output: {
        // Ensure everything is in one file
        inlineDynamicImports: true,
      },
    },
  },
  resolve: {
    alias: {
      // Ensure consistent module resolution
      buffer: 'buffer',
    },
  },
  define: {
    'process.env.NODE_ENV': JSON.stringify('production'),
    global: 'globalThis',
  },
});
