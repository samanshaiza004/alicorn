# Alicorn website

Alicorn's website: a product overview, source-build guide, and project
documentation. It uses Astro for the portal and Starlight for the documentation
route.

## Build locally

~~~sh
cd website
npm install
npm run dev
~~~

The front page is at <code>http://localhost:4321/</code>; documentation starts
at <code>/docs/</code>. Search is indexed by Pagefind during the production
build.

~~~sh
npm run build
npm run preview
~~~

The deployable static site is written to <code>website/dist/</code>. Set
<code>PUBLIC_SITE_URL</code> to the chosen public origin when building so
canonical and social URLs point to the deployed site. The project domain has
not been set in this source yet.

## Structure

| Path | Contents |
|---|---|
| <code>src/pages/</code> | Landing page, source-build information, and project notes. |
| <code>src/layouts/PortalLayout.astro</code> | Shared page shell, metadata, navigation, and copy behavior. |
| <code>src/components/portal/</code> | Landing-page sections. |
| <code>src/components/docs/</code> | Starlight title, search, and footer overrides. |
| <code>src/styles/portal.css</code> | Responsive site design. |
| <code>src/styles/docs.css</code> | Alicorn palette and typography for Starlight. |
| <code>src/content/docs/docs/</code> | Public guide. |
| <code>src/data/site.ts</code> | Shared project facts and links. |
| <code>public/assets/</code> | Product screenshots. |
| <code>public/fonts/</code> | Bundled Atkinson Hyperlegible fonts and notices. |

The repository documentation remains the normative, detailed reference.
Website pages summarize it and link to the relevant source files.

## Deploy

Build the <code>website</code> directory with <code>npm run build</code> and
publish <code>dist/</code> from the static host selected for the Alicorn
website. Supply <code>PUBLIC_SITE_URL</code> in that host's build environment
after the public domain is chosen.
