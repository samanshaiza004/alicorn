/**
 * Shared Alicorn facts and links for the portal and documentation chrome.
 */
export const repository = 'https://github.com/samanshaiza004/alicorn';
export const alikitRepository = 'https://github.com/samanshaiza004/alicorn-kit';

export const site = {
  name: 'Alicorn',
  tagline: 'Direct to write. Retained to run.',
  description:
    'Alicorn is an experimental native GUI runtime for Odin. AliKit is its optional source-level component library. Both keep application data and policy in your app.',
  repository,
  issues: repository + '/issues',
  releases: repository + '/releases',
  source: repository + '/tree/master',
} as const;

export const channels = [
  { label: 'OVERVIEW', href: '/' },
  { label: 'GET STARTED', href: '/docs/getting-started/first-app' },
  { label: 'RUNTIME MODEL', href: '/docs/concepts/retained-runtime' },
  { label: 'API & EXAMPLES', href: '/docs/reference/api-and-examples' },
  { label: 'ALIKIT', href: '/alikit' },
  { label: 'BUILD', href: '/downloads' },
];

export const facts = [
  { label: 'LANGUAGE', value: 'Odin' },
  { label: 'NATIVE HOST', value: 'SDL3 · SDL_GPU' },
  { label: 'STATE', value: 'Owned by your application' },
  { label: 'RUNTIME', value: 'Retained · dirty-driven' },
  { label: 'MATURITY', value: 'Experimental' },
];

export const footerLinks = [
  { label: 'Documentation', href: '/docs' },
  { label: 'Examples', href: '/docs/reference/api-and-examples' },
  { label: 'AliKit components', href: '/alikit' },
  { label: 'AliKit source', href: alikitRepository },
  { label: 'Source', href: repository },
  { label: 'Issues', href: repository + '/issues' },
  { label: 'License', href: repository + '/blob/master/LICENSE' },
];

export const jumpTargets = [
  { label: 'First native app', href: '/docs/getting-started/first-app' },
  { label: 'Runtime model', href: '/docs/concepts/retained-runtime' },
  { label: 'Invalidation and identity', href: '/docs/concepts/invalidation' },
  { label: 'Themes and custom controls', href: '/docs/guides/themes-and-components' },
  { label: 'AliKit components', href: '/alikit' },
  { label: 'Accessibility status', href: '/docs/guides/accessibility' },
  { label: 'API and examples', href: '/docs/reference/api-and-examples' },
  { label: 'Build and test', href: '/docs/development/build-and-test' },
  { label: 'Project status', href: '/docs/project/status' },
];

export const docsLinks = [
  { label: 'Getting started', href: '/docs/getting-started/requirements' },
  { label: 'Runtime model', href: '/docs/concepts/retained-runtime' },
  { label: 'Themes and components', href: '/docs/guides/themes-and-components' },
  { label: 'Accessibility', href: '/docs/guides/accessibility' },
  { label: 'AliKit components', href: '/alikit' },
];
