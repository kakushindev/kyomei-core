// Fills the download panel and the hero button from the live GitHub release.
// Only textContent and attributes are set; nothing from the API is ever parsed as HTML.
import {
  archLabel,
  fetchLatestRelease,
  formatSize,
  signingLabel,
  type DmgAsset,
  type ReleaseResult,
} from '../lib/github-releases';
import { sketchAll } from './sketch';

function text(el: Element | null, value: string) {
  if (el) el.textContent = value;
}

function downloadButton(asset: DmgAsset, label: string, primary: boolean): HTMLAnchorElement {
  const a = document.createElement('a');
  a.className = `btn sketch${primary ? ' btn-primary' : ''}`;
  a.dataset.sketch = 'box';
  a.href = asset.url; // the asset's own browser_download_url, validated in parseRelease
  a.rel = 'noopener';
  const span = document.createElement('span');
  span.textContent = label;
  const arrow = document.createElement('span');
  arrow.className = 'btn-arrow';
  arrow.setAttribute('aria-hidden', 'true');
  arrow.textContent = '↓';
  a.append(span, arrow);
  return a;
}

function formatDate(date: Date | null): string {
  if (!date) return 'Unknown';
  return new Intl.DateTimeFormat(undefined, { year: 'numeric', month: 'long', day: 'numeric' }).format(date);
}

function render(result: ReleaseResult, panel: HTMLElement): void {
  const status = panel.querySelector('[data-release-status]');
  const facts = panel.querySelector<HTMLElement>('[data-release-facts]');
  const buttons = panel.querySelector<HTMLElement>('[data-release-buttons]');
  const notes = panel.querySelector<HTMLAnchorElement>('[data-release-notes]');
  const cta = document.querySelector<HTMLAnchorElement>('[data-download-cta]');
  const ctaLabel = document.querySelector('[data-cta-label]');
  const inline = document.querySelector('[data-release-inline]');

  switch (result.status) {
    case 'no-release':
      text(status, 'There is no stable release yet. Builds will appear on GitHub Releases as soon as the first version is tagged.');
      return;
    case 'rate-limited': {
      const when = result.resetAt ? ` Try again after ${result.resetAt.toLocaleTimeString()}.` : '';
      text(status, `GitHub is limiting requests from your network right now.${when} The releases page always works.`);
      return;
    }
    case 'error':
      text(status, `${result.reason} You can still get every build from GitHub Releases.`);
      return;
    case 'no-dmg':
      text(status, `Kyōmei ${result.release.version} is out, but its disk image is not attached yet. Check the release page in a moment.`);
      if (notes) notes.href = result.release.htmlUrl;
      return;
    case 'ok':
      break;
  }

  const { release, download } = result;
  const shown = download.primary ?? download.options[0];
  text(status, `${release.name} is the latest stable release.`);
  text(panel.querySelector('[data-release-version]'), release.version);
  text(panel.querySelector('[data-release-date]'), formatDate(release.publishedAt));
  text(panel.querySelector('[data-release-size]'), download.primary ? formatSize(download.primary.size) : download.options.map((o) => `${archLabel(o.arch)}: ${formatSize(o.size)}`).join(' · '));
  text(panel.querySelector('[data-release-arch]'), download.primary ? archLabel(download.primary.arch) : 'Choose Apple silicon or Intel');
  const signing = signingLabel(release.signing);
  text(panel.querySelector('[data-release-signing]'), signing.text);
  text(panel.querySelector('[data-release-signing-detail]'), signing.detail);

  const sha = shown?.sha256 ?? null;
  const shaEl = panel.querySelector('[data-release-sha]');
  const copy = panel.querySelector<HTMLButtonElement>('[data-copy-sha]');
  if (sha && download.primary) {
    text(shaEl, sha);
    if (copy) {
      copy.hidden = false;
      copy.onclick = async () => {
        try {
          await navigator.clipboard.writeText(sha);
          copy.textContent = 'Copied';
          setTimeout(() => { copy.textContent = 'Copy'; }, 1600);
        } catch {
          copy.textContent = 'Select it';
        }
      };
    }
  } else if (release.checksumUrl) {
    shaEl?.replaceChildren();
    const a = document.createElement('a');
    a.href = release.checksumUrl;
    a.rel = 'noopener';
    a.textContent = 'Download the .sha256 file';
    shaEl?.append(a);
  } else {
    text(shaEl, 'Listed in the release notes');
  }
  if (facts) facts.hidden = false;
  if (notes) notes.href = release.htmlUrl;

  if (buttons) {
    buttons.replaceChildren();
    if (download.primary) {
      buttons.append(downloadButton(download.primary, `Download ${release.version}`, true));
    } else {
      for (const option of download.options) {
        buttons.append(downloadButton(option, `${archLabel(option.arch)} · ${release.version}`, option.arch === 'arm64'));
      }
    }
    sketchAll(buttons);
  }

  if (cta && download.primary) {
    cta.href = download.primary.url;
    text(ctaLabel, `Download for macOS · ${release.version}`);
  } else if (cta) {
    cta.href = '#download'; // let the visitor pick their Mac in the download section
  }
  text(inline, `Latest stable ${release.tag} · ${archLabel(shown?.arch ?? 'unknown')} · ${signing.text} · macOS 14 or later`);
}

export async function hydrateDownload(): Promise<void> {
  const panel = document.querySelector<HTMLElement>('[data-release-panel]');
  if (!panel?.dataset.api) return;
  let cache: Storage | null;
  try { cache = window.sessionStorage; } catch { cache = null; }
  const result = await fetchLatestRelease({ apiUrl: panel.dataset.api, cache, timeoutMs: 8000, retries: 1 });
  render(result, panel);
}
