import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';

export const baseOptions: BaseLayoutProps = {
  nav: {
    title: 'Cinder',
    transparentMode: 'top',
  },
  links: [
    {
      text: 'Documentation',
      url: '/docs',
      active: 'nested-url',
    },
    {
      text: 'Examples',
      url: '/examples',
      active: 'nested-url',
    },
    {
      text: 'GitHub',
      url: 'https://github.com/eukalpia/cinder',
      external: true,
    },
  ],
};
