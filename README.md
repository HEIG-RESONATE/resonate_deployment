# RESONATE deployment

Single-command deployment of the RESONATE system: FastAPI backend (`api`),
Vue/nginx frontend (`frontend`), Chainlit chat agent (`agent`), MongoDB, and
the Docker MCP gateway with its MCP servers. The application images are pulled
prebuilt from GHCR — a deployment machine needs no build step and no
application source beyond this repository.

- `docker-compose.yml` — production: pull-only, no `build:` sections. This is
  what plain `docker compose up` uses.
- `docker-compose.dev.yml` — local development overlay, opt-in via `-f`: adds
  source builds and live reload. Never loaded unless you ask for it.

## Deploying on a fresh machine

Prerequisites: Docker Engine with Compose v2 (tested with Compose v5.3.1),
git, and access to the private `ghcr.io/heig-resonate` packages.

### 1. Clone

```bash
git clone --recurse-submodules <this-repo-url>
cd resonate_deployment
```

The submodules are needed even for pull-only deployments: `config/agent.toml`
is copied from a template inside `Chat-Agent/`.

### 2. Log in to GHCR

The images are **private**. Create a GitHub personal access token with
`read:packages` and:

```bash
docker login ghcr.io -u <github-username>
```

### 3. Create the configuration files

All deployer-supplied files live in `.env` and `./config/`. Each has a
committed `*.example` next to it. A missing file fails `docker compose up`
with a clear "bind source path does not exist" error — nothing starts half
configured.

| File | Purpose | How to create |
|---|---|---|
| `.env` | Mongo root password, MCP gateway bearer token | `cp .env.example .env`, edit |
| `config/api.env` | API admin password + JWT secret | `cp config/api.env.example config/api.env`, edit |
| `config/htpasswd` | HTTP basic-auth users for the web UI and chat | `docker run --rm httpd:2.4-alpine htpasswd -nbB <user> '<password>' > config/htpasswd` |
| `config/agent.toml` | Agent LLM credentials + MCP gateway URL | `cp Chat-Agent/config.example.toml config/agent.toml`, set the `[llm]` values; keep the `docker-mcp-gateway` entry as is |
| `config/secrets.env` | Secrets handed to MCP servers by the gateway | `cp config/secrets.env.example config/secrets.env`, edit (may stay empty) |
| `config/docker-auth.json` | Registry auth the gateway uses to pull MCP server images | `docker --config /tmp/docker-auth login ghcr.io` then `cp /tmp/docker-auth/config.json config/docker-auth.json` |

Do **not** copy your host `~/.docker/config.json` as `config/docker-auth.json`:
host files typically contain `credsStore` or `currentContext` entries that
break inside the gateway container. The file must contain plain `auths`
entries only.

Non-secret MCP gateway configuration (which servers exist and which are
enabled) is versioned in this repo under `./mcp/` — edit and commit rather
than configuring per machine:

- `mcp/my-catalog.yaml` — server catalog (mounted into the gateway at
  `/root/.docker/mcp/catalogs/my-catalog.yaml`)
- `mcp/registry.yaml` — enabled servers
- `mcp/config.yaml` — optional non-secret per-server configuration

### 4. Start

```bash
docker compose pull
docker compose up -d
```

Then open `http://<host>/` (HTTP basic auth from `config/htpasswd`). The chat
is embedded same-origin at `http://<host>/chat/`. The API is published on
`127.0.0.1:8081` only (it has no auth of its own); MongoDB on
`127.0.0.1:27017`.

To update later: `git pull --recurse-submodules`, then repeat the pull/up
commands.

## Local development

With source submodules checked out, add the dev overlay explicitly:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

All three images build locally and the api runs uvicorn with `--reload` on
the mounted source tree.

## Building and publishing images

Done by hand on a linux/amd64 host — the deploy target is amd64, so never
push images built on an arm64 machine. From a clean checkout:

```bash
./build-images.sh
```

The script builds all three contexts, tags each with the parent-repo short SHA
and `latest`, and prints (does not run) the `docker push` commands. Pushing
requires `docker login ghcr.io` with a PAT that has `write:packages`.

## Troubleshooting

**The agent starts but has no tools.** The gateway healthcheck only proves the
HTTP endpoint is up — the gateway reports healthy even when zero MCP servers
loaded, and the agent then starts normally with an empty toolbox, which looks
like an agent bug but isn't. Check `docker compose logs mcp-gateway` for the
`Those servers are enabled: ...` line: if it's missing or lists nothing,
verify `mcp/registry.yaml` names servers that exist in `mcp/my-catalog.yaml`
and that both files were mounted (the same logs print which registry/catalog
paths were read).

**`up` fails with "bind source path does not exist".** One of the
deployer-supplied files from step 3 is missing; the error names which.

**The gateway can't pull MCP server images.** Check `config/docker-auth.json`
contains a valid `auths` entry for `ghcr.io` (the PAT needs `read:packages`).

**Port 8080.** The chat's old standalone vhost on `:8080` is deprecated and
slated for removal; it now just redirects `/` to `/chat/`. Use
`http://<host>/chat/` via port 80.

## What the compose file references

Everything the stack mounts or reads lives inside this repository (`./mcp/`,
`./config/`, `.env`) except `/var/run/docker.sock`, which the MCP gateway
needs to spawn MCP server containers. `$HOME` is not referenced anywhere.
