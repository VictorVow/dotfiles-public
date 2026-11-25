# Self-Hosted - overview & shared infrastructure (`1-COMMON`)

> Copied from the private `Self-Hosted/1-COMMON/README.md` for this public mirror. Relative links below point into the private `Self-Hosted/` monorepo (not published) - kept for context, not navigation. Domains and IPs are placeholder-rewritten.

This is the entry point for the whole **Self-Hosted** monorepo. Each sibling directory is an independent project — its own `docker-compose.yml` + Ansible `deploy.yml` — that deploys one service; they share infrastructure through this `1-COMMON` repo. Start here for the cross-repo picture, then read the target project's own README for service-specific detail.

- [Repository map](#repository-map)
- [How the pieces fit](#how-the-pieces-fit)
- [Deploying: what to run, and when](#deploying-what-to-run-and-when)
- [`host.yml` vs `common.yml` — one-time host setup vs per-deploy](#hostyml-vs-commonyml--one-time-host-setup-vs-per-deploy)
- [Updates](#updates) ([Watchtower vs WUD vs Renovate vs a local script](#watchtower-vs-wud-vs-renovate-vs-a-local-script))
- [Control server: Headscale vs Tailscale Cloud](#control-server-headscale-vs-tailscale-cloud)
- [Tag invocation matrix](#tag-invocation-matrix)
- [Invocation](#invocation)
- [Required variables](#required-variables)
- [SSH lockdown — pre- and post-checks](#ssh-lockdown--pre--and-post-checks)
- [Exported facts](#exported-facts)
- [Longer docs (`docs/`)](#longer-docs-docs)
- [Potential future services](#potential-future-services)

## Repository map

| Repo / dir                                                                                                  | Role                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`1-COMMON`**                                                                                              | Shared Ansible — one-time host setup ([`host.yml`](host.yml): Tailscale, Docker, firewall, VPS baseline) and the per-deploy preflight ([`common.yml`](common.yml)) imported by every app — **plus** the single shared tailnet HTTPS edge for the lord-ubuntu node ([`node-edge.yml`](node-edge.yml) + [`tasks/caddy-edge.yml`](tasks/caddy-edge.yml)), the shared-node service registry ([`node-services.yml`](node-services.yml)), and the deploy orchestrator ([`justfile`](justfile)). |
| **`Headscale-server`**                                                                                      | The self-hosted [Headscale](https://headscale.net/) control plane and the wildcard-cert issuer ("the hub"). Issues `*.device.example.com` and publishes per-service DNS records (derived from [`node-services.yml`](node-services.yml)) via `headscale_extra_records`.                                                                                                                                                                                                                    |
| App repos — `Stremio`, `Git-server`, `logseq-sync`, `DAV`, `RustDesk`, `RSS`, `Feeddeck`, `Flaresolverr`, … | One service each. They `import_playbook: ../1-COMMON/common.yml`, and on the shared node register their edge route in `1-COMMON`'s `node_edge_*` table instead of running their own edge.                                                                                                                                                                                                                                                                                                 |

## How the pieces fit

Several apps share the **lord-ubuntu** node behind ONE tailnet HTTPS edge:

- **`host.yml`** (run once per host with `just host <name>`) installs Tailscale + Docker, joins the Headscale tailnet, and applies the VPS baseline + UFW.
- **`common.yml`** (imported by each app's `deploy.yml`) checks the host was set up, re-converges Tailscale, and exports the `tailscale_ip` / `tailscale_dns` facts apps bind to.
- The **shared node edge** ([`node-edge.yml`](node-edge.yml)) binds `:443` on the node's tailnet IP and terminates HTTPS with the hub-issued wildcard cert (read from a shared S3 store — `node_edge_cert_mode: shared`). Its routing table (`node_edge_*` in [`inventory.lord-ubuntu.yml`](inventory.lord-ubuntu.yml)) fans out to each app's container over a shared `*_internal` Docker network. Apps on this node set `shared_node_edge: true` and deploy only their containers + that network — they do **not** run an edge of their own.
- The **Headscale hub** issues the wildcard and publishes the per-service subdomain DNS records (`headscale_extra_records`); MagicDNS only auto-names _nodes_, so each `<svc>.device.example.com` needs an explicit record.
- The edge vhost and the DNS record for each service are both **derived from the shared [`node-services.yml`](node-services.yml)** registry, so a service is declared once and the two stay in lockstep (see the next section).

## Deploying: what to run, and when

A web service on the shared **lord-ubuntu** node has three facets that used to be declared by hand in three places: its container (its own app repo), its **edge vhost** (`node_edge_*` in [`inventory.lord-ubuntu.yml`](inventory.lord-ubuntu.yml), rendered by [`node-edge.yml`](node-edge.yml)), and its **MagicDNS A record** (`headscale_extra_records` in the [Headscale deploy](../Headscale-server/Headscale-deploy)).

### Single source of truth: `node-services.yml`

The vhost + DNS record (and the docker network the edge joins) are now declared **once** in [`node-services.yml`](node-services.yml). `node-edge.yml` derives its `caddy_edge_vhosts` from it, and the Headscale deploy derives its `headscale_extra_records` from the same file — so the two can no longer drift, and the old "needs a matching Headscale extra_record" hand-syncing is gone. To add or change a shared-node service, edit `node-services.yml` and nothing else.

### Onboarding with `just`

A [`justfile`](justfile) in this directory wraps the deploy commands. Run from `1-COMMON/`; `<svc>` is a path relative to the Self-Hosted root:

```bash
just                                    # list recipes
just host lord-ubuntu                   # ONE-TIME host setup (also: ts-exit, headscale)
just onboard WatchSync/WatchSync-server # NEW service: DNS + edge + service deploy + Dashboard
just deploy  WatchSync/WatchSync-server # routine redeploy of one service
just dns                                # re-publish Headscale DNS records
just edge                               # re-render the shared node Caddy edge
just dashboard                          # redeploy Dashboard (Homepage tiles + Gatus checks)
```

`just` is provided by the shared dev shell in [`flake.nix`](flake.nix), which is also the deploy toolchain for every service repo: each repo's `.envrc` loads it (`use flake ../1-COMMON`), so all deploys run the same Ansible, and `nix flake update` here updates them all (the recipes only need `ansible-playbook` on PATH); ad-hoc, `nix run nixpkgs#just -- --list` works too. None of them prompt for a sudo password: every deploy user (`lord` on lord-ubuntu, `ubuntu` on ts-exit, `don` on Headscale) has NOPASSWD sudo (lord-ubuntu's via `/etc/sudoers.d/90-lord`, added 2026-10-20). For a host that still needs one, pass `-K` as an extra arg (`just host <name> -K`) or run the playbook by hand with `-K`.

### What each recipe wraps

| Recipe (`just …`) | When to run                                                               | Underlying command                                                                                                                                                             |
| ----------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `host <name>`     | **Once per host**, and after changing that host's inventory or `host.yml` | `ansible-playbook -i inventory.<name>.yml host.yml` (`headscale` uses the Headscale-deploy inventory); extra args pass through, e.g. `--tags nfs`, `--check --diff`            |
| `deploy <svc>`    | **Every deploy** of an existing app                                       | `cd ../<svc> && git pull --ff-only && ansible-playbook deploy.yml` (the pull is skipped with a warning if the repo has no upstream; the deploy stops if it can't fast-forward) |
| `dns`             | After a `node-services.yml` change                                        | `cd ../Headscale-server/Headscale-deploy && ansible-playbook -i inventory.yml deploy.yml --tags headscale`                                                                     |
| `edge`            | After a `node-services.yml` change                                        | `ansible-playbook -i inventory.lord-ubuntu.yml node-edge.yml`                                                                                                                  |
| `dashboard`       | After a `node-services.yml` change                                        | `deploy Dashboard`                                                                                                                                                             |
| `onboard <svc>`   | **New** app or subdomain (runs all)                                       | `dns` → `edge` → `deploy <svc>` → `dashboard` (last step skipped when `<svc>` is `Dashboard`)                                                                                  |

So onboarding a **new app or subdomain** is: add it to `node-services.yml`, then `just onboard <svc>`. **Ongoing deploys** of an existing app are just `just deploy <svc>`. It fast-forwards the app repo first, because Renovate automerges image bumps on Forgejo and deploying a stale checkout would put the old tag back. Running `ansible-playbook deploy.yml` in the app repo directly skips that pull, so `git pull` first.

**Why the edge doesn't need re-running on every app deploy:** Caddy reaches each upstream by Docker DNS over a shared `*_internal` network (e.g. `forgejo:3000` over `git_internal`). When a routine `deploy.yml` _recreates_ a container, it rejoins the network with the same service alias and Caddy re-resolves it — the edge keeps working untouched.

Both shared commands are **idempotent**, so re-running when nothing changed is a safe no-op: `node-edge.yml` short-circuits the Caddy reload when the config is byte-identical, and `--tags headscale` skips the image rebuild and only restarts Headscale if `config.yaml` actually changed.

### Checks (`just check`, pre-commit, CI)

Static checks run three ways — manually via `just`, on `git commit` via a tracked hook, and in Forgejo Actions on push. All three reuse the same recipes so they can't drift:

| Recipe              | What it verifies                                                                                                                                                                                                                                                                   |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `just lint`         | `yamllint` over all tracked `*.yml`/`*.yaml`, then `ansible-lint` over the playbooks (skipping `node-services.yml`, which is data not a play).                                                                                                                                     |
| `just readme-check` | `scripts/readme-sync.py --check` — every `<!-- 1-COMMON:* -->` README block matches its snippet/`docs/inventories/` source.                                                                                                                                                        |
| `just edge-check`   | `scripts/check-edge-networks.py` — every `node_services` upstream resolves to a container on an external `*_internal` network that's listed in `node_edge_networks` (catches the "edge can't reach it" gap), plus the reverse (no stale networks the edge joins but nothing uses). |
| `just check`        | All of the above.                                                                                                                                                                                                                                                                  |

The **pre-commit hook** (`.githooks/pre-commit`, enabled once per clone with `just install-hooks`) runs the same checks but only over staged files — `yamllint`/`ansible-lint` on staged YAML, `readme-check`/`edge-check` when a README or `node-services.yml` is staged. Bypass a single commit with `git commit --no-verify`. The hook needs `nix` on PATH; the tools come from this repo's `flake.nix` devShell.

The **Forgejo Actions workflow** ([`.forgejo/workflows/checks.yml`](.forgejo/workflows/checks.yml)) runs `just lint` on push. `readme-check` and `edge-check` can't run in CI — they scan sibling service repos under the Self-Hosted root, which isn't a single git checkout on the runner. They run locally via the hook / `just check` instead.

## `host.yml` vs `common.yml` — one-time host setup vs per-deploy

The shared Ansible is split by how often it needs to run:

| Playbook                   | When it runs                                                                                                                      | What it does                                                                                                                                                                                                                                                                         |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`host.yml`](host.yml)     | **Once per host** (`just host <name>`), and again after changing that host's inventory or anything in `host.yml` / its task files | Tailscale install + join, then converge; VPS baseline (journald cap, earlyoom); UFW firewall; Docker install + `daemon.json` + docker group + swap + `tailscale-docker-routing-fix` + `docker-prune.timer`. Opt-in: `ssh-lockdown`, `nfs`, `netplan`, `update`, `sudo-user-install`. |
| [`common.yml`](common.yml) | **Every service deploy** (each `deploy.yml` and `node-edge.yml` imports it)                                                       | Preflight: fails with a "run `just host`" hint if Docker or Tailscale isn't installed and Running. Then the Tailscale converge: `tailscale set` from inventory, exit-node egress checks + the Docker bridge fix, and the `tailscale_ip` / `tailscale_dns` / `docker_bind_ip` facts.  |

The tasks live in [`tasks/`](tasks): `tailscale-install.yml` and `docker-host.yml` are only used by `host.yml`; `tailscale-converge.yml` is shared by both, so a change to a host's `tailscale_*` inventory (e.g. a new exit node) reaches the node on the next service deploy too.

Everything in `common.yml` is tagged `always`, so tag-filtered service runs (e.g. `just dns`, which is `--tags headscale`) still converge Tailscale and get the facts. The Tailscale parts are also tagged `tailscale`, so `--skip-tags tailscale` skips them on a host that can't join yet (the Headscale VPS before Headscale is up).

### Docker waste prune (`docker-prune.timer`)

`host.yml`'s `docker` tag also installs a systemd timer that reclaims Docker disk waste weekly (Sunday 05:00, with a 5-minute randomized delay and `Persistent=true` so a rebooted Sunday catches up). It runs three conservative prunes in sequence:

- `docker buildx prune -f --filter until=168h` — BuildKit cache **older than 7 days**, keeping the recent hot set for fast rebuilds (this is the big one; unpruned build cache silently eats tens of GB on hosts that build local images).
- `docker image prune -f` — dangling/untagged images only (not `-a`, so tagged images stay available for rollback).
- `docker volume prune -f` — anonymous dangling volumes only (named volumes are preserved by default).

It deliberately avoids `docker system prune` (which also wipes stopped containers and networks) so the prune is targeted. Output lands in journald — inspect a run with `journalctl -u docker-prune`, and trigger an ad-hoc prune with `sudo systemctl start docker-prune`. The units are managed by Ansible under `/etc/systemd/system/docker-prune.{service,timer}`.

### earlyoom

`host.yml`'s `vps-baseline` tag installs `earlyoom` on every host. It kills the largest process once free RAM is at most 5% **and** free swap at most 10%, long before the kernel OOM killer would (which only fires after minutes of thrashing). Added 2026-11 after lord-ubuntu froze twice: once from runaway Vitest workers (30 to 40 GB each) and once from Calibre's headless camoufox (18 GB and 26 GB). The stall also caused hung-task warnings, a systemd-timesyncd watchdog timeout and a tailscaled start failure.

The arguments live in `/etc/default/earlyoom` (written by Ansible, so edit `host.yml`, not the host):

- `--prefer (^|/)(node|Web.Content|chromium|chrome)$`: Node (test runners, agents) and browser processes are killed first.
- `--avoid (^|/)(tailscaled|dockerd|containerd|sshd|systemd|caddy|camoufox-bin)$`: keeps the host reachable and the edge up. `camoufox-bin` is here because Calibre's browser worker never recovers from losing its main process: every later fetch fails with `The camoufox browser failed: The browser process exited` until Calibre restarts. Its `Web Content` tabs stay killable, and `mem_limit` caps the container.
- `-r 0`: no periodic memory report, only kills are logged.

Gotcha: the unit passes `$EARLYOOM_ARGS` unquoted, so systemd splits it on whitespace with no quote handling. Patterns must contain no spaces or quotes, which is why "Web Content" is written `Web.Content`.

Inspect kills with `journalctl -u earlyoom` (and `journalctl -k | grep -i "out of memory"` for any the kernel still did). Per-service caps (e.g. Calibre's `mem_limit: 6g`) sit on top of this: they contain one container, earlyoom protects the whole host.

### Container log rotation (`daemon.json`)

`host.yml`'s `docker` tag sets `"log-driver": "local"` with `max-size: 10m`, `max-file: 5` in `/etc/docker/daemon.json`, so each container keeps at most ~50 MB of rotated, compressed logs. Docker's default `json-file` driver never rotates and will eventually fill the disk. `docker logs` works the same. The setting only applies to containers created after the daemon restart; recreate existing ones (`docker compose up -d --force-recreate`, or wait for their next image update) to move them over. Check a container with `docker inspect -f '{{.HostConfig.LogConfig.Type}}' <name>`.

## Updates

There is no single update mechanism: each stack uses one of the approaches below. The thing to know first is that **a routine deploy does not update images**. Most `deploy.yml`s run `docker compose up -d`, which reuses whatever image is already cached on the host, so a floating tag like `:latest` stays on the build from its last pull until something pulls it again. The per-repo lookup lives in [`docs/inventories/UPDATES.md`](docs/inventories/UPDATES.md) (mirrored into each repo's README as a `1-COMMON:updates` block). Snapshot as of 2026-10-20:

| Approach                                  | Stacks                                                                                                                                                                                                                                          | How a new version arrives                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Scoped Watchtower sidecar**             | Dashboard (Homepage, Gatus, vpn-check), Flaresolverr, FreeLLMAPI, Git-server (Postgres `16-alpine`, Forgejo `10`), Rclone, TTRSS (Postgres `17-alpine`, the Forgejo-registry fork image, web-nginx), Yamtrack (`release` tag, Redis `8-alpine`) | Automatically, every 3 days, once the image behind the tag is at least 2 weeks old (see [Watchtower conventions](#watchtower-conventions)). Floating major/minor tags (`16-alpine`, `10`, `release`) only move within that tag.                                                                                                                                                                                                                                      |
| **Renovate PR (pinned exact tag)**        | Calibre (Calibre + Syncthing), Dashboard's Beszel hub + agent, RustDesk                                                                                                                                                                         | The Git-server stack's `renovate-bot` runs daily at 04:30 and opens a PR bumping the tag to the newest release that is at least 14 days old, then automerges it. `self-hosted-autodeploy.service` then runs `just deploy` for each repo whose waiting commits are all renovate-bot's, and reports to the Notifications hub. Per-repo rules are in each repo's `renovate.json5`. See [Git-server § Renovate](../Git-server/README.md#renovate-dependency-update-prs). |
| **Watchtower present, nothing to update** | Headscale hub, News, Suwayomi                                                                                                                                                                                                                   | Kept for the cleanup pass and for any future registry image. The hub's three services and Suwayomi's fork build (`suwayomi_source=fork`, currently deployed) opt out with `com.centurylinklabs.watchtower.enable=false`, and NewsNow is built locally. Yamtrack's `fork` mode opts out the same way.                                                                                                                                                                 |
| **Cron pull on the host**                 | Redlib (daily, 03:00), DAV/Baïkal (every 3 days, 03:00)                                                                                                                                                                                         | `docker compose pull && docker compose up -d` from a cron job installed by the repo's `deploy.yml`, with no cooldown. Baïkal is pinned to `baikal0.12.1`, so its cron only picks up rebuilds of that tag.                                                                                                                                                                                                                                                            |
| **Cron rebuild from source**              | RSSHub (every 3 days, 03:00)                                                                                                                                                                                                                    | Re-clones upstream RSSHub and rebuilds the image, keeping the custom routes.                                                                                                                                                                                                                                                                                                                                                                                         |
| **Pulled on every deploy**                | logseq-sync                                                                                                                                                                                                                                     | `pull: always` in `deploy.yml`, so each deploy fetches the Forgejo-registry image for `IMAGE_TAG` (`latest` or a pinned build tag). `just update` in the repo does the same by hand.                                                                                                                                                                                                                                                                                 |
| **Pinned exact version**                  | Apprise `2.0.1`, ArchiveBox `0.9.73`, AIOStreams `v2.30.0`, StremThru `0.81.0`, Forgejo runner `6.3.1`, Renovate `44.140.0`, every Watchtower `1.17.1`                                                                                          | Only when the tag in `docker-compose.yml` is bumped and the stack is redeployed.                                                                                                                                                                                                                                                                                                                                                                                     |
| **Floating tag, no updater**              | Stremio stack (AIOMetadata, Comet, Prowlarr, Subsense, Zilean, WUD, and their Redis/Postgres), Nitter + Redis, Egress-proxy on ts-exit (Caddy `2`, HAProxy `lts-alpine`)                                                                        | Never on its own: `:latest` here means "whatever was cached at the last pull". Update with `docker compose pull && docker compose up -d` in the stack's directory on the host.                                                                                                                                                                                                                                                                                       |
| **Built locally**                         | Shared Caddy edge, Kill-The-Newsletter, Miruyomi, Sootio, WatchSync, VideoTracker + ScreenLog, Egress-proxy's tinyproxy, and the fork modes above                                                                                               | Rebuilt when the repo's `deploy.yml` runs and the source has changed.                                                                                                                                                                                                                                                                                                                                                                                                |

Two more things sit outside the table:

- **WUD** (What's Up Docker, deployed by the Stremio repo at `wud-lord-ubuntu.device.example.com`) lists available image updates for every container on lord-ubuntu. It is view-only: no `WUD_TRIGGER_*` is configured, so it neither notifies nor updates.
- **Host packages**: `host.yml`'s opt-in `update` tag (`just host <name> --tags update`) upgrades Tailscale to the latest stable release via apt. These playbooks don't upgrade the rest of the OS.

### Watchtower conventions

Every Watchtower sidecar uses the same block (copy it from an existing stack, e.g. [`Git-server/docker-compose.yml`](../Git-server/docker-compose.yml)), because each line fixes a problem that has actually happened:

- **`ghcr.io/nicholas-fedor/watchtower`, pinned to a fixed tag.** The original `containrrr/watchtower` was archived in Dec 2025, and its Docker client negotiates API v1.25, which Engine 25+ rejects ("client version 1.25 is too old"), sending it into a crash loop. The fork negotiates the API version automatically. It's pinned rather than `:latest` because a self-updating updater is the weakest link in the soak; bump it deliberately.
- **`WATCHTOWER_SCOPE=<stack>` plus the matching `com.centurylinklabs.watchtower.scope=<stack>` label on every service, including the watchtower itself.** Unscoped instances on a shared node treat each other as stale duplicates and remove one another ("removed 1 excess Watchtower instance"), which once left a stack's watchtower deleted and its images frozen. An unscoped watchtower would also update every container on the host.
- **`WATCHTOWER_COOLDOWN_DELAY=2w`.** A supply-chain soak: only adopt an image whose build is at least 2 weeks old, so a bad upstream push has time to be noticed and pulled. The cooldown applies to the image currently behind the tag, not to the newest build that's old enough. An image whose tag is rebuilt more often than every 2 weeks therefore never qualifies and never updates. linuxserver images are rebuilt about weekly, so they don't belong under a watchtower; Calibre uses Renovate instead. A per-container `com.centurylinklabs.watchtower.cooldown-delay` label overrides the delay (`"0"` disables it).
- **`WATCHTOWER_POLL_INTERVAL=259200`** (3 days), **`WATCHTOWER_CLEANUP=true`**, **`WATCHTOWER_INCLUDE_STOPPED=true`** with **`WATCHTOWER_REVIVE_STOPPED=false`**, **`WATCHTOWER_LABEL_ENABLE=false`** (watch everything in scope; opt a container out with `com.centurylinklabs.watchtower.enable=false`), and `command: --debug --cleanup`.
- **No `docker system prune`** in any stack. Image and build-cache cleanup is handled by the host's weekly [`docker-prune.timer`](#docker-waste-prune-docker-prunetimer).

### Watchtower vs WUD vs Renovate vs a local script

Four ways to keep images current, compared for this setup. Watchtower, WUD and Renovate are in use; the local script is not. (`logseq-sync` also has a `renovate.json5`, but Renovate ignores it until `renovate-bot` is added as a collaborator there.)

|                                   | Watchtower (scoped sidecar)                                                                                                               | WUD                                                                                                                                     | Renovate on Forgejo                                                                                                                                                                                                                                                                                                                                | Local script + systemd timer                                                                                                                  |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **What it is**                    | A container per stack that watches that stack's images through the Docker socket                                                          | One container per node that watches every container on it                                                                               | A one-shot container in the Git-server stack, run daily by `git-server-renovate.timer`, that opens PRs as `renovate-bot`                                                                                                                                                                                                                           | A small script installed by the stack's `deploy.yml`, like the existing `calibre-backup.timer`                                                |
| **Which version it picks**        | Only the image behind the tag in use (`:latest`, `16-alpine`, …); never looks at other tags                                               | The newest semver tag across all of the image's tags (narrowed by a `wud.tag.include` regex); for non-semver tags it watches the digest | The newest version in the registry, parsed with a versioning regex (e.g. `^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)-ls(?<build>\d+)$` for linuxserver)                                                                                                                                                                                         | Whatever the script implements, e.g. the newest exact build tag that's newer than the running one and old enough                              |
| **Minimum age (soak)**            | `WATCHTOWER_COOLDOWN_DELAY`, measured against the image behind the tag only; never qualifies on tags rebuilt more often than the cooldown | None                                                                                                                                    | `minimumReleaseAge` per version: proposes the newest version that has passed it (with `internalChecksFilter: strict`, no PR before then)                                                                                                                                                                                                           | Whatever the script implements                                                                                                                |
| **Where release dates come from** | The image config's `created` timestamp (set by whoever built the image)                                                                   | n/a                                                                                                                                     | Docker Hub's `tag_last_pushed`, but only for images with ≤ 1,000 tags (anonymous listing stops at page 10). ghcr.io (and `lscr.io`, which fronts it) and quay.io give no dates. Without a date Renovate ≥ 42 holds the update indefinitely. For the rest, GitHub release dates via a regex custom manager (needs a GitHub token), as Calibre does. | The image config's `created` timestamp from the registry (~3 requests per tag), or GitHub release dates                                       |
| **How the update is applied**     | Pulls and recreates the container itself                                                                                                  | Off here. Triggers can recreate containers (`docker`, `docker-compose`) or notify (Apprise, ntfy, SMTP, …)                              | Opens a PR bumping the tag in `docker-compose.yml`; the host changes when it's merged and the stack is redeployed                                                                                                                                                                                                                                  | Pins the chosen tag (e.g. in a host-side `docker-compose.override.yml`, which `deploy.yml` doesn't overwrite) and runs `docker compose up -d` |
| **Record of what changed**        | Container logs only                                                                                                                       | Its own UI/store                                                                                                                        | Git history and PRs                                                                                                                                                                                                                                                                                                                                | The script's journal; the host-side override file isn't in git                                                                                |
| **Review before updating**        | No                                                                                                                                        | Optional (`WUD_TRIGGER_*_AUTO=false` means run from the UI)                                                                             | Optional: automerge is on here, since the soak happens before a PR exists                                                                                                                                                                                                                                                                          | No                                                                                                                                            |
| **Fits**                          | Stateless or easy-to-rebuild services on a floating tag                                                                                   | A dashboard of pending updates; alerts through the existing Apprise                                                                     | Stateful services pinned to exact versions, where each upgrade should be deliberate and recorded                                                                                                                                                                                                                                                   | Hands-off updates that still pick the newest old-enough build, for one or two images with immutable version tags                              |
| **Watch out for**                 | The scope and pin rules in [Watchtower conventions](#watchtower-conventions)                                                              | Its `docker-compose` trigger edits the compose file on the host, which the next `deploy.yml` overwrites with the repo's copy            | Each repo opts in (`renovate-bot` as a Write collaborator plus a `renovate.json5`), and images need their Docker Hub names. Deploying is a separate step: here `self-hosted-autodeploy` runs `just deploy` on the host after each Renovate run                                                                                                     | Custom code to maintain; registry rate limits on images with many tags (Calibre has ~2,400 on ghcr)                                           |

**Roles, not rivals.** Watchtower and the local script apply updates automatically. Renovate proposes them through git. WUD reports them, and only applies them if a trigger is configured. Picking one updater per stack avoids two tools fighting over the same container, and WUD can sit alongside any of them as a view.

### Which approach for which service

The policy for choosing an updater, by what's at stake when an update goes wrong:

| Kind of service               | Examples                                             | Approach                                                                                                                                                       | Status (2026-10-20)                                                                                                                                                                                                                                                                                           |
| ----------------------------- | ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Stateless or easy to rebuild  | Flaresolverr, Redlib, Nitter, Comet, Gatus, Homepage | Floating tag + scoped Watchtower is fine; a bad update costs a restart                                                                                         | Flaresolverr, Gatus, Homepage done; Redlib on its cron; the Stremio stack and Nitter have no updater yet                                                                                                                                                                                                      |
| Holds data you'd hate to lose | Calibre, RustDesk, Beszel, FreeLLMAPI, Yamtrack      | Pin exact versions; Renovate opens and automerges a PR with the newest version that's at least 14 days old; `self-hosted-autodeploy` deploys it                | Calibre, RustDesk, Beszel done. FreeLLMAPI and Yamtrack stay on Watchtower for now: their images are only on ghcr.io, so they'd need Calibre's GitHub-release-dates rule. FreeLLMAPI's releases match its tags; Yamtrack's carry a `v` prefix its tags don't, and its repo was renamed (`dannyvfilms/Floppy`) |
| Databases                     | Postgres, Redis                                      | Pin the major version (e.g. `16-alpine`); minor updates under Watchtower are safe                                                                              | Done                                                                                                                                                                                                                                                                                                          |
| Locally built images          | Suwayomi fork, Miruyomi, NewsNow, WatchSync          | Neither tool applies; they update when you rebuild. (The TTRSS fork is different: it's pushed to the Forgejo registry, so its watchtower picks up new pushes.) | Done                                                                                                                                                                                                                                                                                                          |

With Renovate covering the pinned services, WUD is optional: keep it as a view of pending updates, or drop it.

## Control server: Headscale vs Tailscale Cloud

`host.yml` joins a control server. **By default that is your self-hosted Headscale** (`tailscale up --login-server=<headscale_login_server>`). To join Tailscale's hosted control plane instead:

- **Per host (persistent):** set `tailscale_control: cloud` in inventory.
- **One-off run:** pass `--tags tailscale-cloud` to `host.yml`.

| Mode                    | When                                                               | Login server                        | Auth key (var → `.env` → fail)      |
| ----------------------- | ------------------------------------------------------------------ | ----------------------------------- | ----------------------------------- |
| **Headscale** (default) | `tailscale_control` unset/`headscale`, no `--tags tailscale-cloud` | `headscale_login_server` (required) | `headscale_authkey` → `HS_AUTHKEY=` |
| **Tailscale Cloud**     | `tailscale_control: cloud` **or** `--tags tailscale-cloud`         | none                                | `tailscale_authkey` → `TS_AUTHKEY=` |

The Headscale VPS itself uses cloud mode — it joins your existing tailnet for admin SSH and can't be its own control server (its inventory sets `tailscale_control: cloud`).

Mint a Headscale pre-auth key from the Headscale project, then set it as `headscale_authkey` in inventory (or `HS_AUTHKEY=<key>` in the consuming project's `.env`):

```bash
cd ../Headscale-server/Headscale-deploy && ansible-playbook -i inventory.yml deploy.yml --tags preauthkey
```

**Moving an already-joined node** to a different control server (e.g. an existing Tailscale Cloud node onto Headscale) needs a fresh registration — set `tailscale_relogin: true` for one `host.yml` run (`just host <name> -e tailscale_relogin=true`), which logs out then re-`up`s against the configured server. Fresh nodes don't need it. (Safe here because Ansible connects over the public `ansible_host`, not the tailnet being dropped.)

## Tag invocation matrix

### `host.yml`

| Tag                 | Default?            | What it does                                                                                                                                                                                                 |
| ------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `tailscale`         | **runs by default** | Install Tailscale, join the control server (Headscale by default), converge settings. `--skip-tags tailscale` skips the join.                                                                                |
| `tailscale-cloud`   | opt-in              | Run only the Tailscale play, joining **Tailscale Cloud** instead of Headscale (equivalent to `tailscale_control: cloud`).                                                                                    |
| `vps-baseline`      | **runs by default** | Cap systemd journal at 100 MB, disable `multipathd.service` + `multipathd.socket`, mask `google-osconfig-agent`, install + enable `earlyoom` (config in `/etc/default/earlyoom`, see [earlyoom](#earlyoom)). |
| `firewall`          | **runs by default** | UFW default deny in / allow out, allow `firewall_allow_ports` (default `["22/tcp"]`, minus `22/tcp` when `ssh_lockdown: true`), allow all on `firewall_tailscale_iface`, enable UFW.                         |
| `docker`            | **runs by default** | Docker Engine + Compose plugin (Ubuntu-only), `daemon.json` (DNS, address pools, log rotation), docker group, swap, routing-fix unit, weekly `docker-prune.timer`.                                           |
| `ssh-lockdown`      | opt-in (`never`)    | Remove the public `22/tcp` UFW rule. Requires `ssh_lockdown: true` in inventory.                                                                                                                             |
| `update`            | opt-in (`never`)    | Upgrade Tailscale to the latest stable release via apt.                                                                                                                                                      |
| `nfs`               | opt-in (`never`)    | NFS export of `/home/lord` to the tailnet (lord-ubuntu).                                                                                                                                                     |
| `netplan`           | opt-in (`never`)    | Prefer the wired NIC over WiFi (lord-ubuntu).                                                                                                                                                                |
| `sudo-user-install` | opt-in (`never`)    | Root-only bootstrap: create a sudo user, then re-run as them.                                                                                                                                                |

### `common.yml` (every deploy)

No tags to choose: the preflight and Tailscale converge are tagged `always` (Tailscale parts also `tailscale`), so they run under any `--tags` filter a service deploy uses.

## Invocation

### Host setup — `host.yml`

For the three hosts with inventories here (`lord-ubuntu`, `ts-exit`) or in the Headscale deploy (`headscale`), use the `just` recipe from `1-COMMON/`:

```bash
just host lord-ubuntu                        # full host setup / re-converge
just host lord-ubuntu --check --diff         # dry run
just host lord-ubuntu --tags nfs             # opt-in extras
just host ts-exit --tags update              # upgrade Tailscale only
just host headscale --skip-tags tailscale    # fresh Headscale VPS, before Headscale is up
```

For any other host (e.g. a fresh VPS with its own `inventory.yml`), run the playbook directly:

```bash
cp 1-COMMON/inventory.yml.example 1-COMMON/inventory.yml
# edit — set ansible_host, ansible_user, ssh key, and
#   headscale_login_server + headscale_authkey (default), or tailscale_authkey for cloud
ansible-playbook -i 1-COMMON/inventory.yml 1-COMMON/host.yml
ansible-playbook -i 1-COMMON/inventory.yml 1-COMMON/host.yml --tags tailscale-cloud   # join Tailscale Cloud instead
```

From a service repo whose `ansible.cfg` merges the shared inventory, `ansible-playbook ../1-COMMON/host.yml` works too (no `-i`).

### Per deploy — `common.yml`

Service repos don't call it directly: their `deploy.yml` starts with `import_playbook: ../1-COMMON/common.yml`. Running it alone re-converges Tailscale (including the exit-node Docker bridge fix) without touching any service:

```bash
ansible-playbook -i inventory.lord-ubuntu.yml common.yml
```

## Required variables

### All tags

| Variable                                                       | Source    | Default    |
| -------------------------------------------------------------- | --------- | ---------- |
| `ansible_user`, `ansible_host`, `ansible_ssh_private_key_file` | inventory | (required) |

### Control server (Tailscale play)

| Variable                                                             | Mode      | Default                                               | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| -------------------------------------------------------------------- | --------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tailscale_control`                                                  | both      | `headscale`                                           | `headscale` or `cloud`. Overridden to `cloud` by `--tags tailscale-cloud`.                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `headscale_login_server`                                             | headscale | (required)                                            | Full URL of your Headscale server, e.g. `https://headscale.example.com`.                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `headscale_authkey`                                                  | headscale | (from `.env`)                                         | Pre-auth key minted on the Headscale server. Falls back to `HS_AUTHKEY=` in `{{ inventory_dir }}/.env`.                                                                                                                                                                                                                                                                                                                                                                                                          |
| `tailscale_authkey`                                                  | cloud     | (from `.env`)                                         | Tailscale Cloud auth key. Falls back to `TS_AUTHKEY=` in `{{ inventory_dir }}/.env`.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `tailscale_relogin`                                                  | both      | `false`                                               | Log out + re-register first — use to switch an already-joined node's control server.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `tailscale_hostname`                                                 | both      | (system hostname)                                     | Hostname registered in the tailnet.                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `tailscale_ssh` / `tailscale_accept_dns` / `tailscale_accept_routes` | both      | `true`                                                | Passed to `tailscale up` / `set`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `tailscale_advertise_exit_node`                                      | both      | `false`                                               | Advertise as exit node (enables IP forwarding).                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `tailscale_exit_node`                                                | both      | `""`                                                  | Route this host's egress through an exit node. Accepts a tailnet peer's MagicDNS name or IP (e.g. `ts-exit`, `100.x.y.z`), **or** a Mullvad relay enrolled as a wg-only peer using its full `mullvad-<relay>` name (e.g. `mullvad-gb-lon-wg-001` — not the bare `gb-lon-wg-001`). Enroll Mullvad relays first via Headscale-deploy `scripts/mullvad-register-node.sh`. Mullvad peers can't disco-pong, so the deploy validates them by egress DNS resolution rather than `tailscale ping`.                       |
| `tailscale_docker_bridge_cidrs`                                      | both      | `172.16.0.0/12` ∪ daemon.json `default-address-pools` | Docker bridge ranges that bypass the exit node (pref-5260 `ip rule … lookup main` + MASQUERADE) so inbound DNAT to containers isn't black-holed out `tailscale0`. Only relevant when `tailscale_exit_node` is set. Auto-derived; override **only** if Docker hands out networks outside the derived set — e.g. when the 172.17–172.31 pool is exhausted and Docker spills compose networks into its built-in `192.168.0.0/16` fallback. The override **replaces** the whole set, so keep `172.16.0.0/12` listed. |

### `firewall` / `ssh-lockdown` tags (`host.yml`)

| Variable                   | Default      | Notes                                                                                                                                                              |
| -------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `firewall_allow_ports`     | `["22/tcp"]` | Public allow list. Set in inventory (e.g. Headscale adds 80/443).                                                                                                  |
| `firewall_tailscale_iface` | `tailscale0` |                                                                                                                                                                    |
| `ssh_lockdown`             | `false`      | Set `true` once public SSH is closed. `firewall` then leaves `22/tcp` out, so default host runs don't re-open it; `--tags ssh-lockdown` refuses to run without it. |

## SSH lockdown — pre- and post-checks

`ssh-lockdown` closes public port 22. If Tailscale SSH isn't working, running it will lock you out — recovery requires the VPS provider's console. Never run it on the Headscale VPS (admin SSH rides on that Headscale; 22 is the break-glass path).

**Before** running it, verify Tailscale SSH from _another_ tailnet-connected device (not from the VPS itself, not via the public IP):

```bash
ssh <ansible_user>@<hostname>.<tailnet>.ts.net    # via MagicDNS
ssh <ansible_user>@100.x.y.z                      # via Tailscale IP
```

Tailscale SSH authenticates via tailnet identity, so you should get a shell with no password or key prompt. If that works, set `ssh_lockdown: true` in the host's inventory (so later default `firewall` runs don't re-open 22), then run the lockdown:

```bash
just host <name> --tags ssh-lockdown
```

**After**, confirm the state:

```bash
ssh -o ConnectTimeout=5 <ansible_user>@<public-ip>    # should time out / be refused
ssh <ansible_user>@<hostname>.<tailnet>.ts.net        # should still work
```

To undo (re-open 22 if Tailscale breaks and you need break-glass access), remove `ssh_lockdown: true` from inventory and re-run `just host <name>` — the allow list includes `22/tcp` by default.

## Exported facts

After the Tailscale converge (`tasks/tailscale-converge.yml`, run by both `common.yml` and `host.yml`), downstream plays see:

| Fact            | Example                     | Purpose                                            |
| --------------- | --------------------------- | -------------------------------------------------- |
| `tailscale_ip`  | `100.x.x.x`                 | Bind project ports to the tailnet-only IP.         |
| `tailscale_dns` | `rustdesk.tail-abcd.ts.net` | Print in deploy summaries; use for client configs. |

Auth key resolution order (for the initial join in `host.yml`):

- **Headscale mode (default):** `headscale_authkey` var → `HS_AUTHKEY=` in `{{ inventory_dir }}/.env` → fail (message points at `--tags preauthkey` on the Headscale project). Also requires `headscale_login_server`.
- **Tailscale Cloud mode:** `tailscale_authkey` var → `TS_AUTHKEY=` in `{{ inventory_dir }}/.env` → fail (message points at the Tailscale admin console).

---

## Longer docs (`docs/`)

Topic docs that don't fit in this README live in [`docs/`](docs):

| Doc                                          | What it covers                                                                                                                                                                                                                                                                                                                                                                                              |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`docs/gcp-ts-exit.md`](docs/gcp-ts-exit.md) | The **ts-exit** GCP exit-node VM end to end: tooling (`gcloud`, `tofu`), Terraform recreate flow, ephemeral-IP and firewall rules, joining the tailnet with a Headscale pre-auth key, Gatus/Beszel/Homepage monitoring, a full Standard-vs-Premium cost breakdown, the £5 budget alert, and troubleshooting (including the 2026-07 billing incident).                                                       |
| [`docs/snippets/`](docs/snippets/)           | Canonical README blocks each service repo embeds via `<!-- 1-COMMON:* -->` markers and keeps in sync with `scripts/readme-sync.py` (`just readme-sync` / `readme-check`) — shared-node inventory, `just host` setup, node-identity warning, dev-shell notes, idempotency and `.env` notes. See [`docs/snippets/README.md`](docs/snippets/README.md) for the substitution tokens and the full snippet table. |
| [`docs/inventories/`](docs/inventories/)     | Per-service inventories mirrored into service READMEs via `readme-sync.py` — [`STATE.md`](docs/inventories/STATE.md) (data paths + backup state of each lord-ubuntu service, feeds `1-COMMON:state` blocks) and [`UPDATES.md`](docs/inventories/UPDATES.md) (how each repo's images stay current — Watchtower / Renovate / cron / pull / manual — feeds `1-COMMON:updates` blocks).                         |
