// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';

// The public URL is configurable (PUBLIC_SITE_URL) so staging hosts work without code changes.
const site = process.env.PUBLIC_SITE_URL ?? 'https://kyomei.kakushin.dev';

export default defineConfig({
  site,
  output: 'static',
  trailingSlash: 'ignore',
  build: {
    // External stylesheets only: the Nginx CSP allows no inline styles or scripts.
    inlineStylesheets: 'never',
    assets: '_assets',
  },
  integrations: [sitemap({ filter: (page) => !page.includes('/404') })],
  vite: { plugins: [tailwindcss()] },
});
