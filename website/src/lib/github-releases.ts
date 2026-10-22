// Resolves the latest stable Kyōmei release from the GitHub REST API at runtime, in the browser.
//
// Why runtime: the site is static. Resolving "latest" at build time would freeze the download
// button on whatever existed when the site was built. Fetching here means a new release shows
// up as soon as it is published, with no rebuild or redeploy.
//
// `/releases/latest` returns the most recent non-draft, non-prerelease release, which is what the
// page calls "Latest stable release". The response is still validated defensively.
//
// This module has no DOM dependencies so it can be unit tested; scripts/download.ts renders it.

export type Arch = 'universal' | 'arm64' | 'x86_64' | 'unknown';
export type Signing = 'notarized' | 'signed' | 'unsigned' | 'unknown';

export interface DmgAsset {
  name: string;
  url: string;
  size: number;
  arch: Arch;
  /** Lower-case hex SHA-256 when GitHub reports a digest for the asset. */
  sha256: string | null;
}

export interface Release {
  tag: string;
  version: string;
  name: string;
  publishedAt: Date | null;
  htmlUrl: string;
  signing: Signing;
  dmgs: DmgAsset[];
  /** URL of a published `.sha256` file for the primary download, if one exists. */
  checksumUrl: string | null;
}

export type ReleaseResult =
  | { status: 'ok'; release: Release; download: DownloadChoice }
  | { status: 'no-dmg'; release: Release }
  | { status: 'no-release' }
  | { status: 'rate-limited'; resetAt: Date | null }
  | { status: 'error'; reason: string };

export interface DownloadChoice {
  /** The one asset to offer directly, or null when the user must choose. */
  primary: DmgAsset | null;
  /** Every valid option (for "choose your Mac" when there is more than one). */
  options: DmgAsset[];
}

const SEMVER_TAG = /^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const ALLOWED_DOWNLOAD_HOSTS = new Set(['github.com', 'objects.githubusercontent.com']);

// ── Parsing ──────────────────────────────────────────────────────────────────

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const str = (v: unknown): string | null => (typeof v === 'string' && v.length > 0 ? v : null);

function safeHttpsUrl(v: unknown, hosts?: Set<string>): string | null {
  const s = str(v);
  if (!s) return null;
  try {
    const u = new URL(s);
    if (u.protocol !== 'https:') return null;
    if (hosts && !hosts.has(u.hostname)) return null;
    return u.toString();
  } catch {
    return null;
  }
}

export function classifyArch(name: string): Arch {
  const n = name.toLowerCase();
  if (/universal/.test(n)) return 'universal';
  const arm = /(arm64|aarch64|apple[-_ ]?silicon)/.test(n);
  const intel = /(x86[-_]?64|amd64|intel)/.test(n);
  if (arm && !intel) return 'arm64';
  if (intel && !arm) return 'x86_64';
  // Kyōmei's own pipeline publishes one universal image named Kyomei-X.Y.Z-macOS.dmg.
  if (/^kyomei-\d+\.\d+\.\d+-macos\.dmg$/.test(n)) return 'universal';
  return 'unknown';
}

export function parseSigning(body: string | null): Signing {
  if (!body) return 'unknown';
  const marker = /<!--\s*kyomei:signing=(notarized|signed|unsigned)\s*-->/.exec(body);
  return marker ? (marker[1] as Signing) : 'unknown';
}

function parseDigest(v: unknown): string | null {
  const s = str(v);
  const m = s && /^sha256:([0-9a-f]{64})$/i.exec(s);
  return m ? m[1].toLowerCase() : null;
}

/** Validates a `/releases/latest` payload. Returns null for anything that is not a usable release. */
export function parseRelease(json: unknown): Release | null {
  if (!isRecord(json)) return null;
  if (json.draft === true || json.prerelease === true) return null;
  const tag = str(json.tag_name);
  const htmlUrl = safeHttpsUrl(json.html_url, new Set(['github.com']));
  if (!tag || !SEMVER_TAG.test(tag) || !htmlUrl) return null;

  const published = str(json.published_at);
  const publishedAt = published && !Number.isNaN(Date.parse(published)) ? new Date(published) : null;
  const assets = Array.isArray(json.assets) ? json.assets.filter(isRecord) : [];

  const dmgs: DmgAsset[] = [];
  const checksums = new Map<string, string>();
  for (const asset of assets) {
    const name = str(asset.name);
    const url = safeHttpsUrl(asset.browser_download_url, ALLOWED_DOWNLOAD_HOSTS);
    if (!name || !url) continue;
    if (asset.state !== undefined && asset.state !== 'uploaded') continue;
    if (name.toLowerCase().endsWith('.dmg')) {
      const size = typeof asset.size === 'number' && Number.isFinite(asset.size) && asset.size > 0 ? asset.size : 0;
      if (size === 0) continue; // an empty or still-uploading asset must never become a button
      dmgs.push({ name, url, size, arch: classifyArch(name), sha256: parseDigest(asset.digest) });
    } else if (name.toLowerCase().endsWith('.dmg.sha256')) {
      checksums.set(name.slice(0, -'.sha256'.length), url);
    }
  }

  const version = tag.replace(/^v/, '');
  const choice = chooseDownload(dmgs);
  const primaryName = choice.primary?.name ?? dmgs[0]?.name;
  return {
    tag,
    version,
    name: str(json.name) ?? `Kyōmei ${version}`,
    publishedAt,
    htmlUrl,
    signing: parseSigning(str(json.body)),
    dmgs,
    checksumUrl: primaryName ? (checksums.get(primaryName) ?? null) : null,
  };
}

/**
 * Picks what to offer. One image, or one universal image among several, is offered directly.
 * Several architecture-specific images are offered as a choice. Images whose architecture cannot
 * be told apart are not guessed at: the user is sent to choose on GitHub instead.
 */
export function chooseDownload(dmgs: DmgAsset[]): DownloadChoice {
  if (dmgs.length === 0) return { primary: null, options: [] };
  if (dmgs.length === 1) return { primary: dmgs[0], options: dmgs };
  const universal = dmgs.filter((d) => d.arch === 'universal');
  if (universal.length === 1) return { primary: universal[0], options: universal };
  const arm = dmgs.filter((d) => d.arch === 'arm64');
  const intel = dmgs.filter((d) => d.arch === 'x86_64');
  if (universal.length === 0 && arm.length === 1 && intel.length === 1) {
    return { primary: null, options: [arm[0], intel[0]] };
  }
  return { primary: null, options: [] }; // ambiguous: do not point at a file that may be wrong
}

// ── Fetching ─────────────────────────────────────────────────────────────────

export interface FetchOptions {
  apiUrl: string;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
  retries?: number;
  cache?: Pick<Storage, 'getItem' | 'setItem'> | null;
  cacheTtlMs?: number;
  now?: () => number;
}

interface CachedEntry {
  at: number;
  payload: unknown;
}

function readCache(opts: FetchOptions): unknown | undefined {
  try {
    const raw = opts.cache?.getItem(`kyomei-release:${opts.apiUrl}`);
    if (!raw) return undefined;
    const entry = JSON.parse(raw) as CachedEntry;
    const now = (opts.now ?? Date.now)();
    if (typeof entry.at !== 'number' || now - entry.at > (opts.cacheTtlMs ?? 10 * 60_000)) return undefined;
    return entry.payload;
  } catch {
    return undefined;
  }
}

function writeCache(opts: FetchOptions, payload: unknown): void {
  try {
    const entry: CachedEntry = { at: (opts.now ?? Date.now)(), payload };
    opts.cache?.setItem(`kyomei-release:${opts.apiUrl}`, JSON.stringify(entry));
  } catch {
    /* storage full or blocked: the cache is only an optimisation */
  }
}

export function resultFromPayload(payload: unknown): ReleaseResult {
  const release = parseRelease(payload);
  if (!release) return { status: 'error', reason: 'The release data from GitHub was not in the expected format.' };
  const download = chooseDownload(release.dmgs);
  if (!download.primary && download.options.length === 0) return { status: 'no-dmg', release };
  return { status: 'ok', release, download };
}

/** Fetches and interprets the latest release. Never throws. */
export async function fetchLatestRelease(opts: FetchOptions): Promise<ReleaseResult> {
  const cached = readCache(opts);
  if (cached !== undefined) return resultFromPayload(cached);

  const fetchImpl = opts.fetchImpl ?? fetch;
  const attempts = 1 + Math.max(0, opts.retries ?? 1);
  let lastReason = 'GitHub could not be reached.';

  for (let attempt = 0; attempt < attempts; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 8000);
    try {
      const response = await fetchImpl(opts.apiUrl, {
        headers: { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
        signal: controller.signal,
        credentials: 'omit',
      });
      if (response.status === 404) return { status: 'no-release' };
      const remaining = response.headers.get('x-ratelimit-remaining');
      if (response.status === 429 || (response.status === 403 && remaining === '0')) {
        const reset = Number(response.headers.get('x-ratelimit-reset'));
        return { status: 'rate-limited', resetAt: Number.isFinite(reset) && reset > 0 ? new Date(reset * 1000) : null };
      }
      if (!response.ok) {
        lastReason = `GitHub answered with HTTP ${response.status}.`;
        if (response.status < 500) break; // client errors will not fix themselves on retry
        continue;
      }
      let payload: unknown;
      try {
        payload = await response.json();
      } catch {
        return { status: 'error', reason: 'GitHub returned a response that is not JSON.' };
      }
      const result = resultFromPayload(payload);
      if (result.status === 'ok' || result.status === 'no-dmg') writeCache(opts, payload);
      return result;
    } catch (error) {
      lastReason = error instanceof DOMException && error.name === 'AbortError'
        ? 'GitHub took too long to answer.'
        : 'GitHub could not be reached.';
    } finally {
      clearTimeout(timer);
    }
  }
  return { status: 'error', reason: lastReason };
}

// ── Formatting helpers (pure) ────────────────────────────────────────────────

export function formatSize(bytes: number): string {
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
}

export function archLabel(arch: Arch): string {
  switch (arch) {
    case 'universal': return 'Universal · Apple silicon and Intel';
    case 'arm64': return 'Apple silicon';
    case 'x86_64': return 'Intel';
    default: return 'macOS';
  }
}

export function signingLabel(signing: Signing): { text: string; detail: string } {
  switch (signing) {
    case 'notarized':
      return { text: 'Signed and notarized', detail: 'Developer ID signed and notarized by Apple. Opens normally.' };
    case 'signed':
      return { text: 'Signed, not notarized', detail: 'Developer ID signed. macOS asks once before the first launch.' };
    case 'unsigned':
      return { text: 'Unsigned build', detail: 'Not notarized. macOS blocks the first launch until you allow it in Privacy & Security.' };
    default:
      return { text: 'Signature not stated', detail: 'See the release notes for how this build was signed.' };
  }
}
