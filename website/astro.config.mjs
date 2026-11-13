// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const repository = 'https://github.com/samanshaiza004/alicorn';

export default defineConfig({
  site: process.env.PUBLIC_SITE_URL || undefined,
  trailingSlash: 'ignore',
  build: { format: 'directory' },
  server: { port: Number(process.env.PORT) || 4321 },
  integrations: [
    starlight({
      title: 'Alicorn',
      description:
        'An experimental native GUI runtime for Odin. Direct to write, retained to run.',
      tagline: 'Direct to write. Retained to run.',
      favicon: '/favicon.svg',
      customCss: ['./src/styles/docs.css'],
      editLink: { baseUrl: repository + '/edit/master/website/' },
      lastUpdated: false,
      pagination: true,
      credits: false,
      disable404Route: true,
      social: [{ icon: 'github', label: 'GitHub', href: repository }],
      components: {
        SiteTitle: './src/components/docs/SiteTitle.astro',
        Search: './src/components/docs/Search.astro',
        Footer: './src/components/docs/Footer.astro',
      },
      head: [
        { tag: 'meta', attrs: { name: 'theme-color', content: '#f1eee5' } },
      ],
      sidebar: [
        {
          label: 'Start here',
          items: [
            { slug: 'docs' },
            { slug: 'docs/getting-started/requirements' },
            { slug: 'docs/getting-started/first-app' },
          ],
        },
        { label: 'Concepts', items: [{ autogenerate: { directory: 'docs/concepts' } }] },
        { label: 'Guides', items: [{ autogenerate: { directory: 'docs/guides' } }] },
        { label: 'API and examples', items: [{ autogenerate: { directory: 'docs/reference' } }] },
        { label: 'Development', items: [{ autogenerate: { directory: 'docs/development' } }] },
        { label: 'Project', items: [{ autogenerate: { directory: 'docs/project' } }] },
      ],
    }),
  ],
});
