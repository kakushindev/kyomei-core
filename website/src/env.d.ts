interface ImportMetaEnv {
  readonly PUBLIC_SITE_URL?: string;
  readonly PUBLIC_GITHUB_REPO?: string;
}
interface ImportMeta {
  readonly env: ImportMetaEnv;
}
