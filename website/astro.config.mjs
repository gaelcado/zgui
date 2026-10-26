// @ts-check
import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import mdx from '@astrojs/mdx';
import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';
import { unified } from '@astrojs/markdown-remark';
import {
  rehypeCode,
  remarkCodeTab,
  remarkHeading,
  remarkStructure,
} from 'fumadocs-core/mdx-plugins';

// Fumadocs' Markdown features on Astro's unified processor: heading ids and
// the table of contents, search's structured data, and Shiki highlighting
// in both themes.
const rehypeCodeOptions = {
  themes: { light: 'github-light', dark: 'github-dark' },
  // Markdown pages render outside React: no language icons for a code block component to show.
  icon: false,
  langs: ['rust', 'luau', 'sh', 'json', 'toml', 'powershell', 'text', 'wgsl', 'swift', 'diff', 'yaml', 'python'],
};

export default defineConfig({
  site: 'https://zgx.zeron.sh',
  trailingSlash: 'never',
  devToolbar: { enabled: false },
  build: { format: 'file' },
  prefetch: { prefetchAll: true, defaultStrategy: 'hover' },
  markdown: {
    // Fumadocs' rehypeCode highlights; Astro's own Shiki would run first.
    syntaxHighlight: false,
    processor: unified({
      remarkPlugins: [remarkHeading, remarkCodeTab, [remarkStructure, { exportAs: 'structuredData' }]],
      rehypePlugins: [[rehypeCode, rehypeCodeOptions]],
    }),
  },
  integrations: [react(), mdx({ extendMarkdownConfig: true, syntaxHighlight: false }), sitemap()],
  vite: { plugins: [tailwindcss()] },
});
