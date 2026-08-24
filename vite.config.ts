import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  resolve: { alias: aliases },
  // ponytail: default 4kb inlines SVGs as data-URLs; bare # in strokes
  // truncates CSS url() so chat canvas tiles render as blank paper.
  build: {
    assetsInlineLimit: 0,
  },
});
