# EyeVoice VDS deployment

Production layout:

- `/opt/eyevoice` — application source
- `/etc/eyevoice/site.env` — website environment variables
- `eyevoice-site.service` — Next.js managed by systemd
- Caddy — public HTTP/HTTPS reverse proxy with automatic TLS

## Repository areas

EyeVoice remains one monorepo, but every product area can have its own commit:

- `site/` — website;
- `Sources/`, `Resources/`, `Package.swift` — macOS application;
- `supabase/` — database migrations and Edge Functions;
- `deploy/` and `.github/workflows/` — infrastructure and automation.

For example, commit only website changes with:

```sh
git add site/
git commit -m "site: update landing page"
git push origin main
```

A push to `main` that changes `site/**` triggers
`.github/workflows/deploy-site.yml`. Application-only commits do not trigger
the website deployment.

The workflow requires these GitHub Actions repository secrets:

- `VDS_HOST` — production server IP;
- `VDS_USER` — restricted deployment user;
- `VDS_SSH_KEY` — its dedicated private key.

The VDS user may only upload source to its home directory and run the fixed,
root-owned `/usr/local/sbin/eyevoice-deploy-site` command. The command builds a
staging release, swaps it into production after a successful build, checks the
local endpoint, and restores the previous release if the health check fails.

Deploy source without local build products:

```sh
rsync -az --delete \
  --exclude .git --exclude .build --exclude build \
  --exclude site/node_modules --exclude site/.next \
  ./ ubuntu@SERVER:/tmp/eyevoice-release/
```

After syncing, install dependencies and build as the `eyevoice` service user,
then restart `eyevoice-site.service`. Never commit or copy private provider keys
into the public website bundle.
