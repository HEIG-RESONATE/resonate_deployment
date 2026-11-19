# ATTENTION: armasuisse will need to reconfigure:

- the gmail account (change password and phone number) 
- setup a telegram account
- the x account (change password and phone number)

See creds.txt for access

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
- `docker-compose.tls.yml` — optional HTTPS overlay, opt-in via `-f`: puts
  Caddy in front as a TLS terminator. See "HTTPS (optional)" below.

## Deploying on a fresh machine

### In case there's no git and/or Docker installed

For git:


```bash
sudo apt update
sudo apt install -y git

git --version
git config --global user.name "Abraham Rubinstein"
git config --global user.email "abraham.rubinstein@gmail.com"
```

For Docker:

```bash
# Add Docker's official GPG key:
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Check status:

```bash
sudo systemctl status docker
```

If not running:

```bash
sudo systemctl start docker
```

Prerequisites: Docker Engine with Compose v2 (tested with Compose v5.3.1),
git, and access to the private `ghcr.io/heig-resonate` packages. (**ACCESS IS NOW PUBLIC TO SIMPLIFY PROCESS**)

### 1. Clone

```bash
git clone --recurse-submodules <this-repo-url>
cd resonate_deployment
```

```bash
git clone --recurse-submodules git@github.com:HEIG-RESONATE/resonate_deployment.git
cd resonate_deployment
```

The submodules are needed even for pull-only deployments: `config/agent.toml`
is copied from a template inside `Chat-Agent/`.

### 2. Log in to GHCR (**ACCESS IS NOW PUBLIC TO SIMPLIFY PROCESS - No need for login**)

The images are **private**, so a token is required even for pulling. GHCR does
**not** accept your GitHub account password — you must use a **classic
personal access token** (github.com → Settings → Developer settings →
Personal access tokens → Tokens (classic)). Using an account password fails
with an opaque `denied: denied` that looks like a typo'd password.

Scopes depend on your role:

- **Deploying (pull only):** `read:packages`
- **Building and pushing the images:** `write:packages`

```bash
docker login ghcr.io -u <github-username>
```

Paste the PAT at the `Password:` prompt.

### We need an MCP gateway token. It will be generated on the gateway first run. (The one already present in the config file might work)

```bash
docker run \                                                                                                                                          
    --name mcp \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
docker logs mcp
```

Then, copy the bearer key starting with ``mcp-``

### Generate a JWT secret

```bash
openssl rand -hex 64
```

Save for api.env

### config/agent.toml

```
[llm]
base_url = "https://litellm.intlab.ch/v1"
api_key = "sk-o02Ny6i2dRxIImI8L_xxIw"
model = "zai-org/GLM-5.2-FP8"

# Optional reasoning control for OpenAI-compatible endpoints (ignored for
# Anthropic): "default" (endpoint decides), "none" (disable thinking),
# "low", "medium", "high", "max". GLM-5.x only honors "none", "high"
# (balanced) and "max" (deepest, its default); it treats low/medium as max.
reasoning_effort = "none"

system_prompt = """You are a helpful AI assistant with access to tools via MCP (Model Context Protocol).
Available tools come from multiple MCP servers as indicated by the [server_name] prefix in tool descriptions. You can use any combination of tools to help the user.
This is an interactive conversation. The user can ask follow-up questions and you should maintain context from previous exchanges.
Key guidelines:
1. Always start by finding out the current date, time and timezone.
2. Use tools to gather information, perform actions, and solve problems. BE PROACTIVE!!!
3. Be conversational and refer back to previous interactions when relevant.
4. Always cross-reference multiple sources, not only from news medias but also leverage the power of social media too. Do prioritize x/twitter!
5. Desired workflow: use X/Twitter, then Telegram (World News channel, there's a chat open), web search for news and photos/images, then before and after satellite images when possible or when it applies to the issue being investigated.
6. If you need to perform multiple related actions, plan your approach, explain it and execute it.
7. Always explain what you're doing when using tools. Say exactly why you are calling a tool just before calling and briefly explain what you got right after.
8. Handle errors gracefully and try alternative approaches if needed.
9. Keep responses concise but informative.
10. Present photos, images, diagrams, etc. whenever possible to substanciate your analysis.
11. When presenting images, diagrams, or photos, always verify the URL is directly accessible before including it in the response. Search engine proxy URLs (e.g., imgs.search.brave.com, t0.gstatic.com, Bing image CDN) are session-bound, cryptographically signed, and expire — they will appear broken to the user. Extract and present only the original source URL from the publisher's domain, or explicitly warn the user if the image cannot be verified as accessible.
12. When saving media URLs to databases, store both the ephemeral proxy reference (for traceability) and the original publisher URL, with a boolean verified_accessible flag. Before writing, perform a lightweight HTTP HEAD check on the original URL to confirm it returns 200 OK. If the original is paywalled, blocked, or unavailable, flag it as proxied_only: true so future queries know the image exists but cannot be hotlinked.
13. Use satellite imagery only for stories involving observable physical or geographic change, such as natural disasters, conflicts, infrastructure damage, or environmental events. Do not use satellite imagery for political statements, interviews, court proceedings, or other stories where the evidence is documentary, testimonial, or institutional rather than geographic.
14. When downloading satellite imagery, always provide output_path=/app/images/<descriptive_filename>.png to save directly to disk. Use the path returned in saved_to to upload the image via resonate_upload_event_image.
"""

[display]
# Show every discovered MCP tool in the startup message. The connected-server
# and total-tool counts are always shown.
show_mcp_tool_list = false

[[mcp_servers]]
name = "docker-mcp-gateway"
type = "streamable-http"
url = "http://mcp-gateway:8811/mcp"
```

### For telegram

We need a ``TELEGRAM_API_ID`` and a ``TELEGRAM_API_HASH``. They can be obtained from [https://my.telegram.org/apps](https://my.telegram.org/apps)

Then, 

```bash
git clone https://github.com/chigwell/telegram-mcp.git
cd telegram-mcp
uv sync
uv run session_string_generator.py
```
Follow the prompts. Save the generated session string securely. It will be configured in ``config/secrets.env`` with the api id and hash. 

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
| `config/docker-auth.json` | Registry auth the gateway uses to pull MCP server images | See "Creating config/docker-auth.json" below |

#### Creating `config/docker-auth.json`

Do **not** copy your host `~/.docker/config.json`: host files typically
contain `credsStore` or `currentContext` entries that break inside the
gateway container. The file must contain plain `auths` entries only.

For the PAT (personal access token):
``GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)`

Generate new token, tick read:packages (and write:packages if pushing)

Generate it with an isolated config directory (use a `read:packages` classic
PAT as the password — see step 2):

```bash
docker --config /tmp/docker-auth login ghcr.io -u <github-username>
```

```bash
cp /tmp/docker-auth/config.json config/docker-auth.json
```

**Then verify it** — if the host docker uses a credential helper
(`credsStore`, e.g. `pass`), the login may have written the credential to the
external store instead, leaving this file without a usable value. It then
copies fine but silently fails to authenticate later:

```bash
cat config/docker-auth.json
```

You must see an `auths` → `ghcr.io` entry with a non-empty base64 `auth`
value, and no `credsStore` key:

```json
{"auths": {"ghcr.io": {"auth": "<base64>"}}}
```

If the `auth` value is missing or empty, write the file by hand:

```bash
printf '{"auths":{"ghcr.io":{"auth":"%s"}}}\n' "$(printf '%s:%s' '<github-username>' '<PAT>' | base64 -w0)" > config/docker-auth.json
```

Non-secret MCP gateway configuration (which servers exist and which are
enabled) is versioned in this repo under `./mcp/` — edit and commit rather
than configuring per machine:

- `mcp/my-catalog.yaml` — server catalog (mounted into the gateway at
  `/root/.docker/mcp/catalogs/my-catalog.yaml`)
- `mcp/registry.yaml` — enabled servers
- `mcp/config.yaml` — non-secret per-server configuration, loaded via the
  gateway's `--config` flag. Supplies the `{{server.key}}` template values
  that catalog entries reference (e.g. `resonate-mcp.api_base_url`); this is
  the vendored home of the old `~/.docker/mcp/my-config.yaml`. A server whose
  catalog entry references a template with no default will fail to start if
  its value is missing here. The gateway spawns servers onto the compose
  project network, so compose service names like `api` are the correct
  targets for in-cluster URLs.

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

## HTTPS (optional)

The base compose serves plain HTTP on port 80. To add TLS without changing any
of that, layer in the Caddy overlay — it puts Caddy in front on ports 80 and
443, obtains a certificate, and reverse-proxies to the frontend. The base file
is untouched; you select HTTPS at run time:

```bash
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d
```

Set two values in `.env` first (templates are in `.env.example`):

- `SITE_ADDRESS` — the public hostname to serve, e.g.
  `resonate.iict-heig-vd.ch`. Caddy automatically obtains and renews a
  **Let's Encrypt** certificate for it and redirects HTTP→HTTPS.
- `ACME_EMAIL` — contact address for Let's Encrypt registration.

**Requirements for the automatic certificate:** this host must be reachable
from the public internet on **ports 80 and 443**, and DNS for `SITE_ADDRESS`
must point directly at it (not at an institutional reverse proxy). Caddy uses
port 80 for the ACME challenge and the redirect. If the box is not directly
reachable, automatic issuance fails — you would then supply an
institution-issued certificate instead (not covered here).

The issued certificate and ACME account persist in the `caddy-data` named
volume; keep it, or every restart re-issues and can hit Let's Encrypt rate
limits. When running under HTTPS, set `public_base_url` in `mcp/config.yaml` to
the `https://` form of your host.

To verify the overlay locally without a public domain, set
`SITE_ADDRESS=localhost`: Caddy serves with its own local CA (browsers warn,
which is expected) so you can confirm the proxy path before deploying.

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
requires `docker login ghcr.io` with a **classic PAT** that has
`write:packages` (pasted at the password prompt — GHCR rejects account
passwords with `denied: denied`).

For the MCP server images, see
[docs/PUBLISHING-MCP-SERVERS.md](docs/PUBLISHING-MCP-SERVERS.md).

## Troubleshooting

**The agent starts but has no tools.** The gateway healthcheck only proves the
HTTP endpoint is up — the gateway reports healthy even when zero MCP servers
loaded, and the agent then starts normally with an empty toolbox, which looks
like an agent bug but isn't. Check `docker compose logs mcp-gateway` for the
`Those servers are enabled: ...` line: if it's missing or lists nothing,
verify `mcp/registry.yaml` names servers that exist in `mcp/my-catalog.yaml`
and that both files were mounted (the same logs print which registry/catalog
paths were read).

**A specific MCP server crashes with `KeyError: '<SOME_VAR>'` in the gateway
logs.** Its catalog entry references a `{{server.key}}` template that has no
value. Check that (a) the gateway command includes
`--config=/root/.docker/mcp/config.yaml`, and (b) `mcp/config.yaml` actually
contains the referenced key. Without `--config` the gateway does not read the
file at all and the env var is never passed (an absent var, not an empty one).

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
