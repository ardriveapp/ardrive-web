/**
 * Build script for bundling @ardrive/turbo-sdk for browser usage.
 *
 * The turbo-sdk has a /web export that's designed for browser usage,
 * but it still has some Node.js imports that need to be shimmed.
 *
 * Run: npm install && npm run build
 * Output: ../turbo-sdk.bundle.min.js
 */

const esbuild = require('esbuild');
const path = require('path');

// Shim for Node.js built-ins that the SDK references but doesn't actually use in browser
const nodeShimPlugin = {
  name: 'node-shim',
  setup(build) {
    // Shim 'stream' - provide minimal PassThrough/Readable/Transform stubs
    build.onResolve({ filter: /^stream$/ }, args => ({
      path: args.path,
      namespace: 'node-shim',
    }));

    build.onResolve({ filter: /^node:stream$/ }, args => ({
      path: args.path,
      namespace: 'node-shim',
    }));

    // Shim 'crypto' - use Web Crypto API
    build.onResolve({ filter: /^crypto$/ }, args => ({
      path: args.path,
      namespace: 'node-shim',
    }));

    build.onLoad({ filter: /.*/, namespace: 'node-shim' }, args => {
      if (args.path === 'stream' || args.path === 'node:stream') {
        return {
          contents: `
            // Minimal stream shim for browser
            export class PassThrough {
              constructor() { this.chunks = []; }
              write(chunk) { this.chunks.push(chunk); return true; }
              end() {}
              read() { return this.chunks.length ? this.chunks.shift() : null; }
              on() { return this; }
              once() { return this; }
              pipe(dest) { return dest; }
            }
            export class Readable extends PassThrough {}
            export class Transform extends PassThrough {}
            export default { PassThrough, Readable, Transform };
          `,
          loader: 'js',
        };
      }

      if (args.path === 'crypto') {
        return {
          contents: `
            // Use Web Crypto API with stubs for Node.js crypto features
            export function randomBytes(size) {
              const bytes = new Uint8Array(size);
              crypto.getRandomValues(bytes);
              return bytes;
            }
            export function createHash(algorithm) {
              let data = new Uint8Array(0);
              return {
                update(chunk) {
                  if (typeof chunk === 'string') {
                    chunk = new TextEncoder().encode(chunk);
                  }
                  const newData = new Uint8Array(data.length + chunk.length);
                  newData.set(data);
                  newData.set(chunk, data.length);
                  data = newData;
                  return this;
                },
                async digest(encoding) {
                  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
                  const hashArray = new Uint8Array(hashBuffer);
                  if (encoding === 'hex') {
                    return Array.from(hashArray).map(b => b.toString(16).padStart(2, '0')).join('');
                  }
                  return hashArray;
                }
              };
            }
            // Stub for createSign - only used by RSA signing which we don't use in browser
            export function createSign(algorithm) {
              return {
                update(data) { return this; },
                sign(key, encoding) { throw new Error('RSA signing not supported in browser'); }
              };
            }
            // RSA padding constants - only used by RSA which we don't use in browser
            export const constants = {
              RSA_PKCS1_PSS_PADDING: 6,
              RSA_PSS_SALTLEN_DIGEST: -1,
            };
            export default { randomBytes, createHash, createSign, constants };
          `,
          loader: 'js',
        };
      }

      return { contents: 'export default {};', loader: 'js' };
    });
  },
};

async function build() {
  try {
    await esbuild.build({
      entryPoints: ['turbo-sdk-entry.js'],
      bundle: true,
      format: 'esm',
      platform: 'browser',
      target: ['es2020'],
      outfile: '../turbo-sdk.bundle.min.js',
      minify: true,
      sourcemap: false,
      plugins: [nodeShimPlugin],
      // Don't fail on warnings about circular dependencies
      logLevel: 'warning',
    });

    console.log('✅ Build complete: turbo-sdk.bundle.min.js');

    // Show file size
    const fs = require('fs');
    const stats = fs.statSync('../turbo-sdk.bundle.min.js');
    const sizeKB = (stats.size / 1024).toFixed(1);
    console.log(`   Size: ${sizeKB} KB`);

  } catch (error) {
    console.error('❌ Build failed:', error);
    process.exit(1);
  }
}

build();
