import type { APIRoute } from 'astro';
import { createFromSource } from 'fumadocs-core/search/server';
import { getStructuredData, source } from '@/lib/source';

// The static search index: one JSON file, searched in the browser.
const server = createFromSource(source, {
  language: 'english',
  buildIndex(page) {
    return {
      id: page.url,
      title: page.data.title,
      description: page.data.description,
      structuredData: getStructuredData(page.data._raw),
      url: page.url,
    };
  },
});

export const GET: APIRoute = () => server.staticGET();
