#!/bin/sh
# Runs the kyomei-web container on the server. Installed as /usr/local/bin/kyomei-deploy and used as
# the forced command of the GitHub Actions deploy key, so that key can do these three things and
# nothing else (no shell, no forwarding):
#
#   deploy <commit-sha>   read a gzipped `docker save` of kyomei-web:<sha> on stdin, start it,
#                         health-check it, and go back to the running version if it fails
#   rollback              switch to the version that ran before the last deploy
#   status                show what is running
#
# Over SSH the command comes from SSH_ORIGINAL_COMMAND; run by hand it takes arguments
# (e.g. `kyomei-deploy rollback`, as a user in the docker group). See docs/DEPLOYMENT.md.
#
# Settings (environment, or edit the defaults here):
#   KYOMEI_WEB_PORT   8080   host port on 127.0.0.1 that the host nginx proxies to
set -eu
set -f   # the command comes from the network: never expand globs in it

NAME=kyomei-web
IMAGE=kyomei-web
PORT="${KYOMEI_WEB_PORT:-8080}"
MAX_IMAGE_BYTES=524288000   # refuse streams over 500 MB
LOCK="${TMPDIR:-/tmp}/kyomei-deploy.lock"

log() { printf 'kyomei-deploy: %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }

case "$PORT" in *[!0-9]*|'') die "KYOMEI_WEB_PORT must be a number" ;; esac

# shellcheck disable=SC2086 # word splitting is intended; globbing is off
set -- ${SSH_ORIGINAL_COMMAND:-${*:-status}}
action="${1:-status}"

lock() {
  mkdir "$LOCK" 2>/dev/null || die "another deploy is running (remove $LOCK if it is not)"
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM
}

image_id() { docker image inspect -f '{{.Id}}' "$1" 2>/dev/null || true; }
running_image() { docker inspect -f '{{.Image}}' "$NAME" 2>/dev/null || true; }
revision_of() { docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$1" 2>/dev/null || true; }

start() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" \
    --restart unless-stopped \
    -p "127.0.0.1:$PORT:8080" \
    --read-only --tmpfs /tmp \
    --cap-drop ALL --security-opt no-new-privileges:true \
    "$1" >/dev/null
}

# Healthy means nginx answers its health endpoint and serves the home page, from inside the container.
probe() {
  i=0
  while [ "$i" -lt 20 ]; do
    if docker exec "$NAME" wget -q -O /dev/null http://127.0.0.1:8080/healthz 2>/dev/null &&
       docker exec "$NAME" wget -q -O /dev/null http://127.0.0.1:8080/ 2>/dev/null; then
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  return 1
}

# Switch to $1; returns 0 when it is healthy. Otherwise starts $2 again (when given) and returns 1
# if that worked, 2 if nothing healthy is running now.
switch() {
  new="$1" old="$2"
  if start "$new" && probe; then
    return 0
  fi
  log "the new container did not pass its health check; last log lines:"
  docker logs --tail 20 "$NAME" >&2 2>&1 || true
  if [ -n "$old" ] && start "$old" && probe; then
    log "kept the previous version ($(revision_of "$old"))"
    return 1
  fi
  [ -n "$old" ] || docker rm -f "$NAME" >/dev/null 2>&1 || true
  log "no healthy version is running; check: docker logs $NAME"
  return 2
}

# Of the images this script loaded (tagged with a commit sha), keep the running and rollback ones.
prune() {
  keep_a="$(running_image)" keep_b="$(image_id "$IMAGE:previous")"
  docker image ls "$IMAGE" --format '{{.Tag}}' | while read -r tag; do
    printf '%s' "$tag" | grep -Eq '^[0-9a-f]{7,40}$' || continue
    ref="$IMAGE:$tag"
    id="$(image_id "$ref")"
    if [ "$id" != "$keep_a" ] && [ "$id" != "$keep_b" ]; then
      docker image rm "$ref" >/dev/null 2>&1 && log "removed old image $ref" || true
    fi
  done
  docker image prune -f --filter "label=org.opencontainers.image.title=kyomei-web" >/dev/null 2>&1 || true
}

case "$action" in
  deploy)
    [ "$#" -eq 2 ] || die "usage: deploy <commit-sha>"
    sha="$2"
    printf '%s' "$sha" | grep -Eq '^[0-9a-f]{7,40}$' || die "invalid commit sha"
    lock
    loaded="$(head -c "$MAX_IMAGE_BYTES" | gunzip -c | docker load 2>&1)" || die "could not load the image: $loaded"
    printf '%s\n' "$loaded" | grep -qx "Loaded image: $IMAGE:$sha" || die "the stream did not contain $IMAGE:$sha"
    [ "$(revision_of "$IMAGE:$sha")" = "$sha" ] || die "$IMAGE:$sha is not labelled with revision $sha"
    previous="$(running_image)"
    log "starting $sha (was: $( [ -n "$previous" ] && revision_of "$previous" || echo nothing))"
    if ! switch "$IMAGE:$sha" "$previous"; then
      [ "$(running_image)" = "$(image_id "$IMAGE:$sha")" ] || docker image rm "$IMAGE:$sha" >/dev/null 2>&1 || true
      die "deploy of $sha failed"
    fi
    if [ -n "$previous" ] && [ "$previous" != "$(running_image)" ]; then
      docker tag "$previous" "$IMAGE:previous"
    fi
    prune
    log "live: $sha on 127.0.0.1:$PORT"
    ;;
  rollback)
    [ "$#" -eq 1 ] || die "usage: rollback"
    lock
    target="$(image_id "$IMAGE:previous")"
    [ -n "$target" ] || die "there is no previous version to roll back to"
    current="$(running_image)"
    [ "$target" != "$current" ] || die "the previous version is already running"
    log "rolling back to $(revision_of "$target")"
    switch "$target" "$current" || die "rollback failed"
    [ -n "$current" ] && docker tag "$current" "$IMAGE:previous"
    log "live: $(revision_of "$target") (roll forward again with: rollback)"
    ;;
  status)
    [ "$#" -eq 1 ] || die "usage: status"
    current="$(running_image)"
    if [ -n "$current" ]; then
      echo "running:  $(revision_of "$current") $(docker inspect -f '{{.State.Status}} since {{.State.StartedAt}}' "$NAME")"
    else
      echo "running:  nothing"
    fi
    previous="$(image_id "$IMAGE:previous")"
    echo "previous: $( [ -n "$previous" ] && revision_of "$previous" || echo none)"
    ;;
  *)
    die "unknown command (allowed: deploy <sha>, rollback, status)"
    ;;
esac
