/**
 * Build script for unified @ardrive/turbo-sdk + @ar.io/sdk browser bundle.
 *
 * This creates a single bundle with both SDKs sharing the same polyfills,
 * which is essential for passing signer objects between them without
 * Buffer type mismatches.
 *
 * Run: npm install && npm run build
 * Output: ../turbo-sdk.bundle.min.js
 */

const esbuild = require('esbuild');
const path = require('path');

// Plugin to provide Node.js polyfills for browser
const nodePolyfillPlugin = {
  name: 'node-polyfill',
  setup(build) {
    // Use globalThis.Buffer instead of bundling our own
    // This ensures we use the same Buffer as ario_sdk.min.js
    build.onResolve({ filter: /^buffer$/ }, args => ({
      path: 'buffer',
      namespace: 'global-buffer',
    }));

    build.onLoad({ filter: /.*/, namespace: 'global-buffer' }, args => ({
      contents: `
        // Use the global Buffer from ario_sdk.min.js
        export const Buffer = globalThis.Buffer;
        export default { Buffer: globalThis.Buffer };
      `,
      loader: 'js',
    }));

    // Shim 'stream' - provide minimal stubs
    build.onResolve({ filter: /^stream$/ }, args => ({
      path: args.path,
      namespace: 'node-polyfill',
    }));

    build.onResolve({ filter: /^node:stream$/ }, args => ({
      path: 'stream',
      namespace: 'node-polyfill',
    }));

    // Shim 'crypto' - use Web Crypto API
    build.onResolve({ filter: /^crypto$/ }, args => ({
      path: args.path,
      namespace: 'node-polyfill',
    }));

    // Shim 'process'
    build.onResolve({ filter: /^process$/ }, args => ({
      path: args.path,
      namespace: 'node-polyfill',
    }));

    build.onLoad({ filter: /.*/, namespace: 'node-polyfill' }, args => {
      if (args.path === 'stream') {
        return {
          contents: `
            // Minimal stream shim for browser
            export class PassThrough {
              constructor() { this.chunks = []; this.listeners = {}; }
              write(chunk) { this.chunks.push(chunk); return true; }
              end(chunk) { if (chunk) this.chunks.push(chunk); }
              read() { return this.chunks.length ? this.chunks.shift() : null; }
              on(event, fn) { this.listeners[event] = this.listeners[event] || []; this.listeners[event].push(fn); return this; }
              once(event, fn) { return this.on(event, fn); }
              emit(event, ...args) { (this.listeners[event] || []).forEach(fn => fn(...args)); }
              pipe(dest) { return dest; }
              unpipe() { return this; }
              destroy() {}
            }
            export class Readable extends PassThrough {
              static from(iterable) {
                const stream = new Readable();
                stream.chunks = Array.isArray(iterable) ? [...iterable] : [iterable];
                return stream;
              }
            }
            export class Writable extends PassThrough {}
            export class Transform extends PassThrough {}
            export class Duplex extends PassThrough {}
            export default { PassThrough, Readable, Writable, Transform, Duplex };
          `,
          loader: 'js',
        };
      }

      if (args.path === 'crypto') {
        return {
          contents: `
            // Use Web Crypto API
            export function randomBytes(size) {
              const bytes = new Uint8Array(size);
              crypto.getRandomValues(bytes);
              return Buffer.from(bytes);
            }
            export function createHash(algorithm) {
              const algo = algorithm.toLowerCase().replace('-', '');
              const algoMap = { sha256: 'SHA-256', sha384: 'SHA-384', sha512: 'SHA-512' };
              let data = new Uint8Array(0);
              return {
                update(chunk) {
                  if (typeof chunk === 'string') chunk = new TextEncoder().encode(chunk);
                  if (Buffer.isBuffer(chunk)) chunk = new Uint8Array(chunk);
                  const newData = new Uint8Array(data.length + chunk.length);
                  newData.set(data);
                  newData.set(chunk, data.length);
                  data = newData;
                  return this;
                },
                digest(encoding) {
                  const hashAlgo = algoMap[algo] || 'SHA-256';
                  return crypto.subtle.digest(hashAlgo, data).then(buf => {
                    const arr = new Uint8Array(buf);
                    if (encoding === 'hex') {
                      return Array.from(arr).map(b => b.toString(16).padStart(2, '0')).join('');
                    }
                    return Buffer.from(arr);
                  });
                }
              };
            }
            export function createSign() {
              return { update() { return this; }, sign() { throw new Error('Not supported in browser'); } };
            }
            export const constants = { RSA_PKCS1_PSS_PADDING: 6, RSA_PSS_SALTLEN_DIGEST: -1 };
            export default { randomBytes, createHash, createSign, constants };
          `,
          loader: 'js',
        };
      }

      if (args.path === 'process') {
        return {
          contents: `
            export const env = {};
            export const nextTick = (fn, ...args) => setTimeout(() => fn(...args), 0);
            export const browser = true;
            export default { env, nextTick, browser };
          `,
          loader: 'js',
        };
      }

      return { contents: 'export default {};', loader: 'js' };
    });
  },
};

// Plugin to inject Buffer global
const bufferGlobalPlugin = {
  name: 'buffer-global',
  setup(build) {
    build.onEnd(() => {
      // The bundle will include buffer, we just need to make sure it's available globally
    });
  },
};

async function build() {
  try {
    // First, install buffer package if not present
    const fs = require('fs');
    if (!fs.existsSync('node_modules/buffer')) {
      console.log('Installing buffer package...');
      require('child_process').execSync('npm install buffer', { stdio: 'inherit' });
    }

    const result = await esbuild.build({
      entryPoints: ['turbo-sdk-entry.js'],
      bundle: true,
      format: 'esm',
      platform: 'browser',
      target: ['es2020'],
      outfile: '../turbo-sdk.bundle.min.js',
      minify: true,
      sourcemap: false,
      plugins: [nodePolyfillPlugin],
      // Inject Buffer global before any other code runs
      inject: ['./buffer-global.js'],
      // Define globals
      define: {
        'global': 'globalThis',
        'process.env.NODE_ENV': '"production"',
      },
      logLevel: 'warning',
      metafile: true,
    });

    console.log('✅ Build complete: turbo-sdk.bundle.min.js');

    // Show file size
    const stats = fs.statSync('../turbo-sdk.bundle.min.js');
    const sizeKB = (stats.size / 1024).toFixed(1);
    const sizeMB = (stats.size / 1024 / 1024).toFixed(2);
    console.log(`   Size: ${sizeKB} KB (${sizeMB} MB)`);

    // Show what's included
    if (result.metafile) {
      const inputs = Object.keys(result.metafile.inputs);
      const turboFiles = inputs.filter(f => f.includes('turbo-sdk')).length;
      const arioFiles = inputs.filter(f => f.includes('@ar.io')).length;
      console.log(`   Includes: ${turboFiles} turbo-sdk files, ${arioFiles} ar.io/sdk files`);
    }

  } catch (error) {
    console.error('❌ Build failed:', error);
    process.exit(1);
  }
}

build();
