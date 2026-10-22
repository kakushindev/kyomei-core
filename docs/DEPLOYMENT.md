# Deploying the website

The landing page ships as a Docker image: the Astro build served by unprivileged nginx on port
8080 inside the container. This guide puts it on a VPS at **kyomei-core.asqara.tech**, behind the
Cloudflare Tunnel that already forwards web traffic to `localhost:80`, and lets GitHub Actions
deploy every change on `main` automatically.

```
 GitHub Actions (on push to main)
   build → test → smoke-test the image
   └─ ssh through Cloudflare Tunnel ─▶ VPS: kyomei-deploy (forced command)
                                           docker load → start → health check → keep or roll back

 visitor ─HTTPS─▶ Cloudflare ─tunnel─▶ cloudflared ─▶ host nginx :80 ─▶ 127.0.0.1:8080 kyomei-web
```

- No registry and no registry credentials: the tested image is streamed over SSH.
- No inbound port: SSH and the website both arrive through the tunnel.
- The deploy key can only run `kyomei-deploy` (deploy, rollback, status). No shell, no
  forwarding, even if the key leaks.
- A deploy that fails its health check never replaces the running site.
- Nothing deploys from pull requests.

You do this setup once. After that, every merge to `main` that touches `website/` goes live by
itself.

---

## 1. On the VPS: Docker and the host nginx

Needed: Docker Engine (<https://docs.docker.com/engine/install/>), nginx on port 80, and
cloudflared as your existing tunnel. Check:

```bash
docker version --format '{{.Server.Version}}' && nginx -v && systemctl is-active cloudflared
sudo systemctl enable docker      # containers come back after a reboot
```

Put these two files from this repository on the server. Upload them with the app you already
use for SSH (most have SFTP), or with `scp` (section 8 shows an SSH config for the tunnel):

- `deploy/nginx/kyomei-core.asqara.tech.conf`
- `deploy/server/kyomei-deploy.sh`

Then, assuming you uploaded them to `/tmp`:

```bash
# Host nginx: route the domain to the container
sudo mv /tmp/kyomei-core.asqara.tech.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/kyomei-core.asqara.tech.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# The deploy command, owned by root so the deploy user cannot change it
sudo install -o root -g root -m 755 /tmp/kyomei-deploy.sh /usr/local/bin/kyomei-deploy
```

(Without `sites-available`, put the nginx file in `/etc/nginx/conf.d/` instead.)

The container will listen on `127.0.0.1:8080`. If 8080 is taken (`sudo ss -ltnp | grep :8080`),
pick another port, change `proxy_pass` in the nginx file, and see the note in step 2.

## 2. On the VPS: a deploy user that can only deploy

```bash
sudo adduser --disabled-password --gecos "" kyomei-deploy
sudo usermod -aG docker kyomei-deploy
sudo install -d -o kyomei-deploy -g kyomei-deploy -m 700 /home/kyomei-deploy/.ssh
```

Being in the `docker` group is as powerful as root, which is why this user's key is locked to
one command in the next step.

## 3. A key for GitHub Actions

On your Mac (or any machine):

```bash
ssh-keygen -t ed25519 -f ~/kyomei_actions -N "" -C "github-actions kyomei-core"
cat ~/kyomei_actions.pub
```

On the VPS, allow that public key for `kyomei-deploy`, **only** for the deploy command. Use one
line, with your key in place of `ssh-ed25519 AAAA…`:

```bash
echo 'restrict,command="/usr/local/bin/kyomei-deploy" ssh-ed25519 AAAA…your-key… github-actions kyomei-core' \
  | sudo tee /home/kyomei-deploy/.ssh/authorized_keys
sudo chown kyomei-deploy:kyomei-deploy /home/kyomei-deploy/.ssh/authorized_keys
sudo chmod 600 /home/kyomei-deploy/.ssh/authorized_keys
```

Another port than 8080? Write `command="KYOMEI_WEB_PORT=8081 /usr/local/bin/kyomei-deploy"`.

The private key (`~/kyomei_actions`, the file without `.pub`) goes into GitHub in step 6. After
that, delete it from your Mac: `rm ~/kyomei_actions ~/kyomei_actions.pub`.

## 4. The server's host key

GitHub Actions refuses to connect unless it knows the server's identity in advance. On the VPS,
with your SSH hostname (the one your SSH app uses through the tunnel, e.g. `ssh.asqara.tech`):

```bash
awk -v h=ssh.asqara.tech '{print h, $1, $2}' /etc/ssh/ssh_host_ed25519_key.pub
```

The output line (`ssh.asqara.tech ssh-ed25519 AAAA…`) is the secret `DEPLOY_SSH_KNOWN_HOSTS`.

## 5. Cloudflare

**Website hostname.** Your tunnel already forwards to `localhost:80`; it needs this hostname too.
Zero Trust → **Networks → Tunnels** → your tunnel → **Public hostname → Add**:
subdomain `kyomei-core`, domain `asqara.tech`, type `HTTP`, URL `localhost:80`. Cloudflare
creates the DNS record. (Config-file tunnels: add
`- hostname: kyomei-core.asqara.tech` / `service: http://localhost:80` above the catch-all, then
`cloudflared tunnel route dns <tunnel> kyomei-core.asqara.tech` and restart cloudflared.)

**SSH hostname.** GitHub Actions connects the way your SSH app does: through a tunnel public
hostname whose service is `ssh://localhost:22`, using `cloudflared access ssh`. If you already
have one, use it. If not, add a public hostname such as `ssh.asqara.tech`, type `SSH`, URL
`localhost:22`.

If that SSH hostname is protected by **Cloudflare Access** (you log in through a browser before
SSH works), automation needs a service token:

1. Zero Trust → **Access → Service auth → Create service token**. Copy the Client ID and Client
   Secret (the secret is shown once).
2. Open the Access application for the SSH hostname → **Policies → Add a policy**, action
   **Service Auth**, include **Service Token** = the token you just made.
3. Store them as `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` in step 6.

No Access application on the SSH hostname? Skip this; the SSH key alone protects it.

## 6. GitHub: secrets and variables

Repository → **Settings → Secrets and variables → Actions**.

**Secrets** tab → *New repository secret*:

| Name | Value |
| --- | --- |
| `DEPLOY_SSH_HOST` | your SSH hostname, e.g. `ssh.asqara.tech` |
| `DEPLOY_SSH_USER` | `kyomei-deploy` |
| `DEPLOY_SSH_KEY` | the whole private key file from step 3, including the `-----BEGIN…` and `-----END…` lines |
| `DEPLOY_SSH_KNOWN_HOSTS` | the line from step 4 |
| `CF_ACCESS_CLIENT_ID` | only with Cloudflare Access (step 5) |
| `CF_ACCESS_CLIENT_SECRET` | only with Cloudflare Access (step 5) |

**Variables** tab → *New repository variable*:

| Name | Value |
| --- | --- |
| `WEBSITE_URL` | `https://kyomei-core.asqara.tech` |
| `WEBSITE_DEPLOY` | `true` (set this last; until then nothing is deployed) |

Optional: **Settings → Environments → production** appears after the first deploy. There you can
require an approval before each deploy, or move the secrets above into the environment so only
the deploy job can read them.

## 7. First deploy

**Actions → Website → Run workflow** (branch `main`). The jobs:

1. *Lint, test and build*: site checks.
2. *Docker image smoke test*: builds the image with `WEBSITE_URL` baked in and tests it.
3. *Deploy to the server*: SSH through the tunnel, `kyomei-deploy deploy <commit>`, then
   `status`, then a request to `https://kyomei-core.asqara.tech/healthz`.

From then on it runs on every push to `main` that changes `website/`. Changes elsewhere (the app,
docs) do not redeploy the site.

On the server you can watch it with `docker ps` and `docker logs kyomei-web`.

## Rolling back

From your own SSH login on the VPS (a user in the `docker` group, or with `sudo`):

```bash
sudo -u kyomei-deploy kyomei-deploy status
sudo -u kyomei-deploy kyomei-deploy rollback     # run again to roll forward
```

Or redeploy an older commit: open its *Website* run in Actions → **Re-run jobs** (the tested
images are kept for 7 days).

## 8. SSH from your Mac through the tunnel (optional)

To use `scp` or `ssh` from a terminal instead of an app: `brew install cloudflared`, then add to
`~/.ssh/config`:

```
Host kyomei-vps
  HostName ssh.asqara.tech
  User <your-user>
  ProxyCommand cloudflared access ssh --hostname %h
```

Now `scp deploy/server/kyomei-deploy.sh deploy/nginx/kyomei-core.asqara.tech.conf kyomei-vps:/tmp/`
and `ssh kyomei-vps` work.

## Firewall

Nothing needs an inbound port. Keep 22, 80 and 8080 closed to the internet if all access goes
through the tunnel. Make sure the tunnel SSH works first so you do not lock yourself out:

```bash
sudo ufw default deny incoming
sudo ufw enable
```

Docker writes its own iptables rules and bypasses ufw for published ports; that is why the
container is published on `127.0.0.1` only.

## Troubleshooting

| Symptom | Likely cause | Check |
| --- | --- | --- |
| Deploy job: `secret DEPLOY_… is not set` | a secret from step 6 is missing | names are case-sensitive |
| `Host key verification failed` | `DEPLOY_SSH_KNOWN_HOSTS` hostname or key does not match | the line must start with exactly `DEPLOY_SSH_HOST` |
| `Permission denied (publickey)` | key not in `authorized_keys`, or wrong user | step 3; `sudo tail /var/log/auth.log` |
| `websocket: bad handshake` / Access login page | SSH hostname is behind Access without a service token | step 5 |
| `unknown command` from kyomei-deploy | someone tried a shell over the deploy key | expected; the key is restricted |
| `deploy of … failed`, site still up | new image failed its health check; old one kept | the job log shows the container's last lines |
| Cloudflare 502 | container down, or nginx points at another port | `docker ps`, `curl -sI -H 'Host: kyomei-core.asqara.tech' http://localhost/` |
| Download says no release | the repository is private: the page asks the public GitHub API, which answers 404 for private repos | works once the repository is public |
| Final `healthz` check warns, deploy is green | Cloudflare bot protection challenged the runner | open the site yourself |

---

## Alternative: deploy by hand with Docker Compose

Without CI, on the VPS, with the repository cloned (private repository: add a read-only deploy
key under **Settings → Deploy keys** and clone with it):

```bash
cd /opt/kyomei/website
printf 'PUBLIC_SITE_URL=https://kyomei-core.asqara.tech\nKYOMEI_WEB_PORT=8080\n' > .env
docker compose up -d --build
./scripts/smoke-test.sh http://127.0.0.1:8080
```

Update: `git pull && docker tag kyomei-web:latest kyomei-web:previous && docker compose up -d --build`.
Roll back: `KYOMEI_WEB_TAG=previous docker compose up -d --no-build`.

Use one method, not both: they run the same container name and port.

If nothing else on the VPS uses port 80, the container can take it directly (`KYOMEI_WEB_PORT=80`,
or `command="KYOMEI_WEB_PORT=80 …"` for CI) and the host nginx is not needed.
