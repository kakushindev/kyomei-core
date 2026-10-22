# Kyōmei landing page: built with Node, served by unprivileged nginx on port 8080.
#
#   docker build -t kyomei-web website/
#   docker run -d --name kyomei-web -p 127.0.0.1:8080:8080 --read-only --tmpfs /tmp kyomei-web
#
# Or use website/compose.yaml. Build arguments set the public URL and the GitHub repository the
# download button reads releases from. See docs/DEPLOYMENT.md.

ARG NODE_VERSION=24.21.0
ARG NGINX_VERSION=1.30.6

FROM node:${NODE_VERSION}-alpine3.24 AS build
WORKDIR /site
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
ARG PUBLIC_SITE_URL=https://kyomei.kakushin.dev
ARG PUBLIC_GITHUB_REPO=kakushindev/kyomei-core
ENV PUBLIC_SITE_URL=${PUBLIC_SITE_URL} PUBLIC_GITHUB_REPO=${PUBLIC_GITHUB_REPO} ASTRO_TELEMETRY_DISABLED=1
# The image is only built if the site passes its unit tests and the dist checks.
RUN npm test && npm run build && node scripts/check-dist.mjs

FROM nginxinc/nginx-unprivileged:${NGINX_VERSION}-alpine3.24
LABEL org.opencontainers.image.title="kyomei-web" \
      org.opencontainers.image.description="Landing page for Kyōmei (共鳴), by Kakushin" \
      org.opencontainers.image.source="https://github.com/kakushindev/kyomei-core" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"
# The image already listens on IPv6 (see default.conf); skip the entrypoint helper notices.
ENV NGINX_ENTRYPOINT_QUIET_LOGS=1
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /site/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
