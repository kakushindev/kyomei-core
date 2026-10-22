# Deploying the website

The landing page ships as a Docker image: the Astro build served by unprivileged nginx on port
8080 inside the container. This guide puts it on a VPS at **kyomei-core.asqara.tech**, behind a
Cloudflare Tunnel that already forwards to `localhost:80`.

```
visitor ──HTTPS──▶ Cloudflare ──tunnel──▶ cloudflared (VPS)
                                              │ http://localhost:80
                                              ▼
                                   host nginx, server_name kyomei-core.asqara.tech
                                              │ http://127.0.0.1:8080
                                              ▼
                                   kyomei-web container (nginx, read-only, non-root)
```

No port is opened to the internet: cloudflared dials out to Cloudflare, nginx and the container
listen on the VPS only.

## 0. What the VPS needs

- Linux (commands below are for Debian/Ubuntu), 512 MB RAM free, about 1 GB disk for images
- Docker Engine with the Compose plugin: <https://docs.docker.com/engine/install/>
  (`docker compose version` must work)
- nginx on the host, listening on port 80 (`sudo apt install nginx` if it is not there yet)
- cloudflared running as your existing tunnel, forwarding to `http://localhost:80`
- `git`

Check:

```bash
docker compose version && nginx -v && systemctl is-active cloudflared
```

## 1. Get the code onto the VPS

The repository is private, so give the VPS a **read-only deploy key** (it can read this one
repository and nothing else).

On the VPS:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/kyomei_deploy -N "" -C "kyomei-core deploy (VPS)"
cat ~/.ssh/kyomei_deploy.pub
```

On GitHub: **kakushindev/kyomei-core → Settings → Deploy keys → Add deploy key**, paste the
public key, leave **Allow write access** unchecked.

Back on the VPS:

```bash
cat >> ~/.ssh/config <<'EOF'
Host github-kyomei
  HostName github.com
  User git
  IdentityFile ~/.ssh/kyomei_deploy
  IdentitiesOnly yes
EOF
sudo mkdir -p /opt/kyomei && sudo chown "$USER" /opt/kyomei
git clone github-kyomei:kakushindev/kyomei-core.git /opt/kyomei
```

(If the repository becomes public, a plain `git clone https://github.com/kakushindev/kyomei-core.git /opt/kyomei` is enough.)

## 2. Configure

Build settings live in `website/.env`, which Compose reads automatically and git ignores:

```bash
cat > /opt/kyomei/website/.env <<'EOF'
PUBLIC_SITE_URL=https://kyomei-core.asqara.tech
PUBLIC_GITHUB_REPO=kakushindev/kyomei-core
KYOMEI_WEB_PORT=8080
EOF
```

- `PUBLIC_SITE_URL` goes into the canonical URL, Open Graph tags and the sitemap.
- `PUBLIC_GITHUB_REPO` is where the download button looks for the latest release.
- `KYOMEI_WEB_PORT` is the loopback port on the VPS. If something already uses 8080 (check with
  `sudo ss -ltnp | grep :8080`), pick another and change `proxy_pass` in step 4 to match.

## 3. Build and start the container

```bash
cd /opt/kyomei/website
docker compose up -d --build
docker compose ps          # STATUS should read "Up … (healthy)" after a few seconds
./scripts/smoke-test.sh http://127.0.0.1:8080
```

The build runs the site's unit tests and dist checks; if any fail, no image is produced and the
running site stays as it was. The smoke test should end with `all checks passed`.

The container restarts on its own after a reboot (`restart: unless-stopped`) as long as the
Docker service is enabled: `sudo systemctl enable docker`.

## 4. Host nginx: route the domain to the container

```bash
sudo cp /opt/kyomei/deploy/nginx/kyomei-core.asqara.tech.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/kyomei-core.asqara.tech.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

(On distributions without `sites-available`, copy the file into `/etc/nginx/conf.d/` instead.)

Test it on the VPS, the same way cloudflared will ask:

```bash
curl -sI -H "Host: kyomei-core.asqara.tech" http://localhost/ | head -5
```

Expect `HTTP/1.1 200 OK` and a `Content-Security-Policy` header. A different page or a 404 from
nginx means another `server` block answered; check `server_name` and `sudo nginx -T | grep -n server_name`.

## 5. Cloudflare Tunnel: add the hostname

Your tunnel already forwards to `localhost:80`. It still needs to know this hostname, and DNS
needs to point the name at the tunnel. Pick the way your tunnel is managed:

**Dashboard (tunnel started with a token):**
Cloudflare Zero Trust → **Networks → Tunnels** → your tunnel → **Public hostname → Add a public hostname**

- Subdomain `kyomei-core`, domain `asqara.tech`
- Service type `HTTP`, URL `localhost:80`
- Save. Cloudflare creates the DNS record for you.

**Config file (`/etc/cloudflared/config.yml`):** add one rule above the catch-all, keep the rest:

```yaml
ingress:
  # … existing rules …
  - hostname: kyomei-core.asqara.tech
    service: http://localhost:80
  - service: http_status:404
```

Then:

```bash
cloudflared tunnel ingress validate
cloudflared tunnel route dns <your-tunnel-name> kyomei-core.asqara.tech
sudo systemctl restart cloudflared
```

If the tunnel already has a wildcard rule such as `*.asqara.tech → http://localhost:80`, only the
DNS record is missing: add a proxied `CNAME kyomei-core → <tunnel-id>.cfargotunnel.com`.

Do not set `httpHostHeader` to another name on this rule: nginx picks the site by the Host header.

## 6. Check from outside

```bash
curl -sI https://kyomei-core.asqara.tech | head -8
```

Then open <https://kyomei-core.asqara.tech> in a browser. The **Download** section shows the
latest release from GitHub. While the repository is **private** it shows "There is no stable
release yet": the page asks the public GitHub API without a token, and the API answers 404 for
private repositories. It finds the release as soon as the repository is public.

## 7. Firewall

Nothing here needs an inbound port. Keep 80 and 8080 closed to the internet, for example with ufw:

```bash
sudo ufw default deny incoming
sudo ufw allow OpenSSH        # or your SSH port
sudo ufw enable
```

Docker writes its own iptables rules and bypasses ufw for published ports. That is why
`compose.yaml` publishes the container on `127.0.0.1` only. Keep it that way.

## Updating

```bash
cd /opt/kyomei && git pull
cd website
docker tag kyomei-web:latest kyomei-web:previous   # keep the running version for a rollback
docker compose up -d --build
./scripts/smoke-test.sh http://127.0.0.1:8080
```

## Rolling back

```bash
cd /opt/kyomei/website
KYOMEI_WEB_TAG=previous docker compose up -d --no-build
```

Back to the newest build later with `docker compose up -d --no-build`.

## Without a host nginx

If nothing else on the VPS uses port 80, the container can take it directly and step 4 is not
needed. Set `KYOMEI_WEB_PORT=80` in `website/.env` and run `docker compose up -d`. The container
answers any Host header, so the tunnel rule from step 5 is all it needs.

## Troubleshooting

| Symptom | Likely cause | Check |
| --- | --- | --- |
| Cloudflare error 1033 | cloudflared is not running or not connected | `systemctl status cloudflared`, `journalctl -u cloudflared -n 50` |
| 502 Bad Gateway | container down or on another port | `docker compose ps`, `docker compose logs --tail 50` |
| Another site's page | nginx `server_name` did not match | step 4 test with the Host header |
| Download says no release | repository private, or no published release | `curl -s -o /dev/null -w '%{http_code}' https://api.github.com/repos/kakushindev/kyomei-core/releases/latest` |
| Old page after an update | browser cache | HTML is sent with `Cache-Control: no-cache`; hard reload. Assets have new names per build |

Logs: `docker compose logs -f` (the container; visitor addresses come from Cloudflare's
`CF-Connecting-IP`) and `/var/log/nginx/kyomei-core.*.log` (host nginx).
