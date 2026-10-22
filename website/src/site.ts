// Every configurable value and every sentence that appears on more than one place lives here.
// Build-time overrides: PUBLIC_SITE_URL and PUBLIC_GITHUB_REPO (see docs/DEPLOYMENT.md).

const env = import.meta.env;

export const site = {
  name: 'Kyōmei',
  asciiName: 'Kyomei',
  kanji: '共鳴',
  kanjiReading: 'kyōmei, resonance',
  tagline: 'Your sound. In harmony.',
  description:
    'Kyōmei is a native macOS app for Soundcore earbuds and headphones: noise cancelling, equalizer, touch controls and battery from your menu bar. Open source, by Kakushin.',
  url: (env.PUBLIC_SITE_URL as string | undefined) ?? 'https://kyomei.kakushin.dev',
  repo: (env.PUBLIC_GITHUB_REPO as string | undefined) ?? 'kakushindev/kyomei-core',
  organization: {
    name: 'Kakushin',
    url: 'https://kakushin.dev',
    github: 'https://github.com/kakushindev',
  },
  license: 'GPL-3.0-or-later',
  minimumMacOS: 'macOS 14 Sonoma',
  disclaimer:
    'Kyōmei is an independent open-source project by Kakushin. It is not affiliated with, endorsed by or sponsored by Anker Innovations or Soundcore. Soundcore is a trademark of its owner.',
} as const;

export const links = {
  repository: `https://github.com/${site.repo}`,
  releases: `https://github.com/${site.repo}/releases`,
  issues: `https://github.com/${site.repo}/issues`,
  contributing: `https://github.com/${site.repo}/blob/main/CONTRIBUTING.md`,
  license: `https://github.com/${site.repo}/blob/main/LICENSE`,
  latestReleaseApi: `https://api.github.com/repos/${site.repo}/releases/latest`,
  openscq30: 'https://github.com/Oppzippy/OpenSCQ30',
} as const;

export const nav = [
  { label: 'Features', href: '/#features', hint: 'What Kyōmei can change on your earbuds.' },
  { label: 'Experience', href: '/#experience', hint: 'Real screens, rendered from the app itself.' },
  { label: 'Download', href: '/#download', hint: 'The latest release, straight from GitHub.' },
  { label: 'GitHub', href: links.repository, hint: 'Source, issues and every release.' },
  { label: 'Kakushin', href: site.organization.url, hint: 'The people who redraw the defaults.' },
] as const;
