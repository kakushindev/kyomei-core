#!/usr/bin/env bash
# Checks a running website container: pages, 404s, cache policy and security headers.
#   website/scripts/smoke-test.sh [base-url]     (default http://127.0.0.1:8080)
set -euo pipefail

base="${1:-http://127.0.0.1:8080}"
failures=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; failures=$((failures + 1)); }

status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
header() { curl -sI "$1" | tr -d '\r' | awk -v h="$(echo "$2" | tr 'A-Z' 'a-z')" 'BEGIN{FS=": "} tolower($1)==h {sub(/^[^:]*: /,""); print; exit}'; }

check_status() {
  local want="$1" path="$2" got
  shift 2
  got="$(status "$@" "$base$path")"
  if [[ "$got" == "$want" ]]; then pass "$path -> $got"; else fail "$path -> $got (want $want)"; fi
}

check_header() {
  local path="$1" name="$2" pattern="$3" got
  got="$(header "$base$path" "$name")"
  if [[ "$got" =~ $pattern ]]; then pass "$path $name: $got"; else fail "$path $name: '${got}' (want /$pattern/)"; fi
}

check_status 200 /
check_status 200 /healthz
check_status 200 /robots.txt
check_status 200 /sitemap-index.xml
check_status 200 /og.png
check_status 404 /does-not-exist
check_status 404 /.env
check_status 405 / -X POST

if curl -s "$base/does-not-exist" | grep -q 'Ky'; then pass "404 serves the site's 404 page"; else fail "404 body is not the site's page"; fi
if curl -s "$base/" | grep -q 'kakushin'; then pass "index.html content"; else fail "index.html content"; fi

asset="$(curl -s "$base/" | grep -o '/_assets/[^"]*\.css' | head -1)"
if [[ -n "$asset" ]]; then
  check_status 200 "$asset"
  check_header "$asset" Cache-Control 'immutable'
else
  fail "no stylesheet linked from index.html"
fi

check_header / Cache-Control '^no-cache$'
check_header / Content-Security-Policy "script-src 'self'"
check_header / Content-Security-Policy 'connect-src .*https://api\.github\.com'
check_header / X-Content-Type-Options '^nosniff$'
check_header / X-Frame-Options '^DENY$'
check_header / Referrer-Policy 'strict-origin-when-cross-origin'
check_header / Server '^nginx$'

gz="$(curl -s -o /dev/null -w '%{size_download}' -H 'Accept-Encoding: gzip' "$base/")"
raw="$(curl -s -o /dev/null -w '%{size_download}' "$base/")"
if (( gz < raw )); then pass "gzip ($raw -> $gz bytes)"; else fail "gzip not applied ($raw / $gz)"; fi

if (( failures > 0 )); then
  echo "smoke-test: $failures failure(s)"
  exit 1
fi
echo "smoke-test: all checks passed"
