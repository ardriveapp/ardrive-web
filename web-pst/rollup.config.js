import commonjs from '@rollup/plugin-commonjs';
import json from '@rollup/plugin-json';
import { nodeResolve } from '@rollup/plugin-node-resolve';
import typescript from '@rollup/plugin-typescript';
import { terser } from 'rollup-plugin-terser';

const commonOutputOpts = {
  format: 'iife',
  name: 'pst',
  globals: {
    // Mock unused dependency, 'util', in 'arweave' and prevent null error.
    'util': 'window'
  },
}

export default {
  input: 'src/index.ts',
  output:  [
    {
      ...commonOutputOpts,
      file: 'dist/pst.js',
    },
    {
      ...commonOutputOpts,
      file: '../web/js/pst.min.js',
      plugins: [terser()],
    }
  ],
  plugins: [
    json(),
    nodeResolve({ browser: true }),
    commonjs(),
    typescript()
  ],
};
