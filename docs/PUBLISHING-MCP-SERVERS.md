# Publishing and updating MCP server images

How to build an MCP server image, publish it to GHCR, and roll it out to a
RESONATE deployment. The application images (api, frontend, agent) are covered
separately in the README, "Building and publishing images" (`build-images.sh`).

## How the pieces fit

- Every custom MCP server is a container image under `ghcr.io/heig-resonate/`.
- The gateway (`mcp-gateway` service) does not build anything. It reads
  `mcp/my-catalog.yaml` (what each server is: image, env, secrets, volumes) and
  `mcp/registry.yaml` (which servers to start), then launches each server as a
  container through the Docker socket.
- The gateway runs server containers with `--pull never`: a new image on GHCR is
  **not** used until it has been pulled on the deployment host.

## Image ↔ source

| Catalog name      | Image (`ghcr.io/heig-resonate/…`) | Source repo |
|-------------------|-----------------------------------|-------------|
| `time-server`     | `time-mcp-server`                 | `Time-MCP-Server` |
| `x-mcp`           | `x-mcp`                           | `xmcp` / `Twitter-MCP-Server` (check which) |
| `osm-mcp`         | `osm-mcp-server`                  | not in ~/mcp-servers on the Mac |
| `geocode-server`  | `geocode-mcp`                     | `geocode-mcp` |
| `telegram-server` | `telegram-mcp`                    | not in ~/mcp-servers on the Mac |
| `resonate-mcp`    | `resonate-mcp`                    | `HEIG-RESONATE/resonate-mcp` |
| `sentinelhub-mcp` | `sentinelhub-mcp`                 | not in ~/mcp-servers on the Mac |
| `gdelt`           | `mcp-gdelt`                       | `mcp-gdelt` (fork of MissionSquad/mcp-gdelt; its GitHub Actions publish to npm, not GHCR) |
| `fetch`, `brave`, `mongodb` | Docker official `mcp/…` images, pinned by digest | not built by us |

TODO: fill in the missing source locations.

## 1. Log in to GHCR (once per build host)

Use a **classic** PAT with `write:packages` (and `read:packages`). GHCR rejects
account passwords with `denied: denied`.

```bash
docker login ghcr.io -u <github-username>    # paste the PAT as the password
```

## 2. Build, tag and push

On the linux/amd64 build server, from the server's repo, at a clean commit:

```bash
cd <server-repo>
git pull
NAME=time-mcp-server                 # image name from the table above
SHA=$(git rev-parse --short HEAD)

docker build \
  -t ghcr.io/heig-resonate/$NAME:$SHA \
  -t ghcr.io/heig-resonate/$NAME:latest .

docker push ghcr.io/heig-resonate/$NAME:$SHA
docker push ghcr.io/heig-resonate/$NAME:latest
```

The SHA tag lets you see what is deployed and roll back; `latest` is what the
catalog points to.

**Building on an arm64 machine (Apple Silicon) instead:** a plain `docker build`
produces an arm64 image that will not run on the servers. Use:

```bash
docker buildx build --platform linux/amd64 \
  -t ghcr.io/heig-resonate/$NAME:$SHA \
  -t ghcr.io/heig-resonate/$NAME:latest --push .
```

## 3. First publish only: package visibility

New GHCR packages are **private** and owned by the org. Either make the package
public, or make sure the PAT in `config/docker-auth.json` can read it:
GitHub → HEIG-RESONATE → Packages → the package → Package settings.
Optionally "Connect repository" there so the package shows the repo's README.

## 4. Roll out to a deployment

On the deployment host:

```bash
docker pull ghcr.io/heig-resonate/$NAME:latest
```

New tool calls use the new image (the gateway starts a fresh server container).
If the server's catalog entry changed (see below), also run, from the
`resonate_deployment` folder:

```bash
git pull
docker compose restart mcp-gateway
```

Then check `docker compose logs mcp-gateway` for the
`Those servers are enabled: ...` line.

To roll back, pull the previous SHA tag and retag it as `latest` locally, or
point the catalog entry at the SHA tag.

## Adding a new server, or changing its config

Edit `mcp/my-catalog.yaml` (and `mcp/registry.yaml` for a new server), commit,
and pull on the deployment host. Custom images are not "self-describing", so
`docker://` references do not work: every server needs a catalog entry.

```yaml
  my-server:
    name: my-server
    title: My MCP Server
    type: server
    image: ghcr.io/heig-resonate/my-server:latest
    description: Short description
    volumes:
      - resonate2_images-data:/app/images      # only if it writes images
    secrets:
      - name: my-server.api_key
        env: API_KEY
    env:
      - name: API_URL
        value: "{{my-server.api_url}}"
```

Non-secret values go in `mcp/config.yaml`; secrets go in `config/secrets.env`.

## Gotchas we hit

- `env` must be a **list** of `{name, value}` objects, never a map. `config`
  must also be a list.
- The gateway gives each server only the config block whose key matches the
  server's **own name**. A server named `gdelt-mcp` with `{{gdelt.*}}`
  templates gets nothing, and its env vars are silently dropped.
- `default:` values in a catalog's config schema are metadata only. Every
  value must actually be present in `mcp/config.yaml`.
- Without `--config=...config.yaml` on the gateway command, config values are
  not passed at all (absent vars, which show up as `KeyError` in the server).
- In `registry.yaml` a server is enabled just by being listed; the
  `enabled: true/false` flag is ignored. To disable a server, remove or comment
  out its entry.
- Servers that save images must mount `resonate2_images-data:/app/images`, and
  any container that needs to read those files (api, agent) must mount the same
  volume. The volume has a fixed `name:` in docker-compose.yml, so every
  compose project (`resonate2`, `rd-test`, ...) shares the same one.
- Avoid `~` in gateway paths (secrets, catalogs): tilde expansion has failed
  silently before. Use absolute paths.
