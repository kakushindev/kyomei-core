import { describe, expect, it, vi } from 'vitest';
import {
  chooseDownload,
  classifyArch,
  fetchLatestRelease,
  formatSize,
  parseRelease,
  parseSigning,
  type DmgAsset,
} from './github-releases';

const API = 'https://api.github.com/repos/kakushindev/kyomei-core/releases/latest';
const SHA = 'd3a4c43c7fe83509c4eceb52bc1e79c53d46a1311ffb1e8e858003b6c3a81dc5';

function asset(name: string, extra: Record<string, unknown> = {}) {
  return {
    name,
    size: 2_958_092,
    state: 'uploaded',
    browser_download_url: `https://github.com/kakushindev/kyomei-core/releases/download/v1.0.0/${name}`,
    ...extra,
  };
}

function release(tag = 'v1.0.0', assets: unknown[] = [asset(`Kyomei-${tag.slice(1)}-macOS.dmg`, { digest: `sha256:${SHA}` }), asset(`Kyomei-${tag.slice(1)}-macOS.dmg.sha256`, { size: 89 })]) {
  return {
    tag_name: tag,
    name: `Kyōmei ${tag.slice(1)}`,
    draft: false,
    prerelease: false,
    published_at: '2026-10-22T07:00:00Z',
    html_url: `https://github.com/kakushindev/kyomei-core/releases/tag/${tag}`,
    body: '<!-- kyomei:signing=unsigned -->\n## 共鳴 Kyōmei',
    assets,
  };
}

function respond(status: number, body: unknown, headers: Record<string, string> = {}) {
  return new Response(typeof body === 'string' ? body : JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...headers },
  });
}

const fetchWith = (...responses: (Response | Error)[]) => {
  const fn = vi.fn<typeof fetch>();
  for (const r of responses) {
    if (r instanceof Error) fn.mockRejectedValueOnce(r);
    else fn.mockResolvedValueOnce(r);
  }
  return fn;
};

describe('parseRelease', () => {
  it('reads a valid stable release and its universal DMG', () => {
    const r = parseRelease(release())!;
    expect(r.tag).toBe('v1.0.0');
    expect(r.version).toBe('1.0.0');
    expect(r.publishedAt?.toISOString()).toBe('2026-10-22T07:00:00.000Z');
    expect(r.signing).toBe('unsigned');
    expect(r.dmgs).toHaveLength(1);
    expect(r.dmgs[0]).toMatchObject({ name: 'Kyomei-1.0.0-macOS.dmg', arch: 'universal', sha256: SHA });
    // The link is the asset's own URL, never one built from a template.
    expect(r.dmgs[0].url).toBe('https://github.com/kakushindev/kyomei-core/releases/download/v1.0.0/Kyomei-1.0.0-macOS.dmg');
    expect(r.checksumUrl).toMatch(/Kyomei-1\.0\.0-macOS\.dmg\.sha256$/);
  });

  it('rejects drafts, prereleases and non-SemVer tags', () => {
    expect(parseRelease({ ...release(), draft: true })).toBeNull();
    expect(parseRelease({ ...release(), prerelease: true })).toBeNull();
    expect(parseRelease({ ...release(), tag_name: 'nightly' })).toBeNull();
  });

  it('rejects malformed payloads', () => {
    expect(parseRelease(null)).toBeNull();
    expect(parseRelease('v1.0.0')).toBeNull();
    expect(parseRelease([])).toBeNull();
    expect(parseRelease({ tag_name: 'v1.0.0' })).toBeNull(); // no html_url
    expect(parseRelease({ ...release(), html_url: 'javascript:alert(1)' })).toBeNull();
  });

  it('ignores empty, half-uploaded and non-GitHub assets', () => {
    const r = parseRelease(release('v1.0.0', [
      asset('Kyomei-1.0.0-macOS.dmg', { size: 0 }),
      asset('Kyomei-1.0.0-arm64.dmg', { state: 'starter' }),
      asset('Kyomei-1.0.0-x86_64.dmg', { browser_download_url: 'https://evil.example/Kyomei.dmg' }),
    ]))!;
    expect(r.dmgs).toHaveLength(0);
  });

  it('treats a missing digest as unknown rather than inventing one', () => {
    const r = parseRelease(release('v1.0.0', [asset('Kyomei-1.0.0-macOS.dmg')]))!;
    expect(r.dmgs[0].sha256).toBeNull();
    expect(r.checksumUrl).toBeNull();
  });
});

describe('classifyArch and chooseDownload', () => {
  const dmg = (name: string): DmgAsset => ({ name, url: `https://github.com/x/${name}`, size: 1, arch: classifyArch(name), sha256: null });

  it('classifies by file name', () => {
    expect(classifyArch('Kyomei-1.0.0-macOS.dmg')).toBe('universal');
    expect(classifyArch('Kyomei-1.0.0-universal.dmg')).toBe('universal');
    expect(classifyArch('Kyomei-1.0.0-arm64.dmg')).toBe('arm64');
    expect(classifyArch('Kyomei-1.0.0-apple-silicon.dmg')).toBe('arm64');
    expect(classifyArch('Kyomei-1.0.0-x86_64.dmg')).toBe('x86_64');
    expect(classifyArch('Kyomei-1.0.0-intel.dmg')).toBe('x86_64');
    expect(classifyArch('Something.dmg')).toBe('unknown');
  });

  it('offers a single image directly', () => {
    expect(chooseDownload([dmg('Kyomei-1.0.0-macOS.dmg')]).primary?.name).toBe('Kyomei-1.0.0-macOS.dmg');
  });

  it('prefers the universal image among several', () => {
    const c = chooseDownload([dmg('Kyomei-1.0.0-arm64.dmg'), dmg('Kyomei-1.0.0-macOS.dmg')]);
    expect(c.primary?.arch).toBe('universal');
  });

  it('asks the user to choose between Apple silicon and Intel', () => {
    const c = chooseDownload([dmg('Kyomei-1.0.0-arm64.dmg'), dmg('Kyomei-1.0.0-x86_64.dmg')]);
    expect(c.primary).toBeNull();
    expect(c.options.map((o) => o.arch)).toEqual(['arm64', 'x86_64']);
  });

  it('refuses to guess between ambiguous images', () => {
    const c = chooseDownload([dmg('a.dmg'), dmg('b.dmg')]);
    expect(c).toEqual({ primary: null, options: [] });
  });
});

describe('parseSigning', () => {
  it('reads the marker written by scripts/release-notes.sh', () => {
    expect(parseSigning('<!-- kyomei:signing=notarized -->')).toBe('notarized');
    expect(parseSigning('<!--kyomei:signing=signed-->')).toBe('signed');
    expect(parseSigning('no marker here')).toBe('unknown');
    expect(parseSigning(null)).toBe('unknown');
  });
});

describe('fetchLatestRelease', () => {
  it('returns the stable release with its download', async () => {
    const result = await fetchLatestRelease({ apiUrl: API, fetchImpl: fetchWith(respond(200, release())), cache: null });
    expect(result.status).toBe('ok');
    if (result.status === 'ok') expect(result.download.primary?.name).toBe('Kyomei-1.0.0-macOS.dmg');
  });

  it('reports no release on 404', async () => {
    const result = await fetchLatestRelease({ apiUrl: API, fetchImpl: fetchWith(respond(404, { message: 'Not Found' })), cache: null });
    expect(result).toEqual({ status: 'no-release' });
  });

  it('reports rate limiting with the reset time', async () => {
    const result = await fetchLatestRelease({
      apiUrl: API,
      fetchImpl: fetchWith(respond(403, { message: 'API rate limit exceeded' }, { 'x-ratelimit-remaining': '0', 'x-ratelimit-reset': '1792656000' })),
      cache: null,
    });
    expect(result.status).toBe('rate-limited');
    if (result.status === 'rate-limited') expect(result.resetAt?.getTime()).toBe(1792656000 * 1000);
  });

  it('reports a release without a DMG', async () => {
    const result = await fetchLatestRelease({
      apiUrl: API, fetchImpl: fetchWith(respond(200, release('v1.0.0', [asset('notes.txt')]))), cache: null,
    });
    expect(result.status).toBe('no-dmg');
  });

  it('turns malformed JSON and bad shapes into an error, never a broken button', async () => {
    expect((await fetchLatestRelease({ apiUrl: API, fetchImpl: fetchWith(respond(200, '{not json')), cache: null })).status).toBe('error');
    expect((await fetchLatestRelease({ apiUrl: API, fetchImpl: fetchWith(respond(200, { hello: 'world' })), cache: null })).status).toBe('error');
  });

  it('retries a server error once, then succeeds', async () => {
    const fetchImpl = fetchWith(respond(502, {}), respond(200, release()));
    const result = await fetchLatestRelease({ apiUrl: API, fetchImpl, cache: null, retries: 1 });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(result.status).toBe('ok');
  });

  it('does not retry client errors', async () => {
    const fetchImpl = fetchWith(respond(401, {}), respond(200, release()));
    const result = await fetchLatestRelease({ apiUrl: API, fetchImpl, cache: null, retries: 1 });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(result.status).toBe('error');
  });

  it('gives up on network failures with a readable reason', async () => {
    const result = await fetchLatestRelease({ apiUrl: API, fetchImpl: fetchWith(new TypeError('offline'), new TypeError('offline')), cache: null });
    expect(result).toEqual({ status: 'error', reason: 'GitHub could not be reached.' });
  });

  it('aborts a request that takes too long', async () => {
    const slow: typeof fetch = (_url, init) => new Promise((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
    });
    const result = await fetchLatestRelease({ apiUrl: API, fetchImpl: slow, cache: null, timeoutMs: 20, retries: 0 });
    expect(result).toEqual({ status: 'error', reason: 'GitHub took too long to answer.' });
  });

  it('follows a new release without any rebuild once the cache expires', async () => {
    const store = new Map<string, string>();
    const cache = { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => void store.set(k, v) };
    let clock = 0;
    const now = () => clock;
    const fetchImpl = fetchWith(respond(200, release('v1.0.0')), respond(200, release('v1.1.0')));

    const first = await fetchLatestRelease({ apiUrl: API, fetchImpl, cache, now, cacheTtlMs: 60_000 });
    clock = 30_000;
    const cached = await fetchLatestRelease({ apiUrl: API, fetchImpl, cache, now, cacheTtlMs: 60_000 });
    clock = 61_000;
    const updated = await fetchLatestRelease({ apiUrl: API, fetchImpl, cache, now, cacheTtlMs: 60_000 });

    expect(first.status === 'ok' && first.release.version).toBe('1.0.0');
    expect(cached.status === 'ok' && cached.release.version).toBe('1.0.0');
    expect(updated.status === 'ok' && updated.release.version).toBe('1.1.0');
    expect(updated.status === 'ok' && updated.download.primary?.name).toBe('Kyomei-1.1.0-macOS.dmg');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });
});

describe('formatSize', () => {
  it('formats bytes for people', () => {
    expect(formatSize(2_958_092)).toBe('2.8 MB');
    expect(formatSize(2048)).toBe('2 KB');
    expect(formatSize(12)).toBe('12 B');
  });
});
