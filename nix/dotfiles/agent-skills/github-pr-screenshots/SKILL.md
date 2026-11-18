---
name: github-pr-screenshots
description: Capture before/after screenshots of a GitHub pull request for any web app (Django, Rails, Laravel, static/SPA, Node…) and optionally post them into the PR description. Checks out the PR head and merge-base in throwaway git worktrees, runs per-repo prepare/serve commands, and screenshots named pages at multiple viewports and colour schemes. Use when a UI PR needs visual proof in its description, or when asked to "screenshot a PR", "add before/after shots", or "post screenshots to the PR".
allowed-tools: Bash Read Write Edit
compatibility: "Requires python 3.11+, playwright (Chromium installed), gh authenticated, and bash. The target repo gets a pr-shots.toml config."

---

Generic PR-screenshotting tool. The parts that never change (worktrees, serving, headless Chromium capture, GitHub upload, PR description rewrite) live in `scripts/pr-screenshots` in this skill; the parts that differ per app (install/migrate/seed/serve, auth, which pages) live in a `pr-shots.toml` you write in the target repo.

## Set up in a repo (first time only)

```
SKILL=~/Projects/installs/nix/dotfiles/agent-skills/github-pr-screenshots
cp "$SKILL/scripts/pr-screenshots" <repo>/scripts/pr-screenshots   # or scripts/
cp "$SKILL/scripts/pr-shots.example.toml" <repo>/pr-shots.toml     # then edit it
echo '.pr-shots/' >> <repo>/.gitignore
chmod +x <repo>/scripts/pr-screenshots
```

Edit `pr-shots.toml` (fully commented; reference below). The minimum is `serve`; add `prepare` commands to install deps/migrate/seed, `[paths]` or `paths_command` for the page map, and `[auth]` if pages sit behind a login.

## Run it

```
cd <repo>
uv run --with playwright python scripts/pr-screenshots 1370 1373   # capture only
uv run --with playwright python scripts/pr-screenshots 1370 --post # then update the PR description
uv run --with playwright python scripts/pr-screenshots 1370 --pages home,library --no-before
```

(`python3` works too if playwright is already importable; `uv run --with playwright` avoids touching the project venv.)

Output lands in `.pr-shots/<pr>/<before|after>/`. **Open the PNGs and look at them before `--post`.**

| Flag | Meaning |
|---|---|
| `--post` | Upload images and rewrite the screenshot section of the PR description |
| `--no-before` | Skip the merge-base capture (new pages have nothing to compare against) |
| `--before-ref <sha>` | Use an explicit ref for the "before" capture instead of the merge-base |
| `--pages a,b` | Override the page list for this run |
| `--no-auth` | Skip the login step even if `[auth]` is configured |
| `--repo owner/name` | Repo that owns the PRs (default: `upstream` remote, else `origin`, else config) |
| `--config <path>` | Config file (default: `pr-shots.toml` at the repo root) |
| `--port N` | Local port for the temporary server (default 8299 or config `port`) |
| `--out-dir <path>` | Output root (default `<repo>/.pr-shots`) |

## What it does

1. Asks `gh` for the PR head commit and the merge-base with its base branch (fetches either SHA from `github.com/<repo>` if missing locally).
2. Creates a throwaway git worktree per commit under `.pr-shots/work/`. The user's checkout is never touched.
3. Per worktree: runs each `prepare` command (env: `WORKTREE`, `ROOT`, `PORT`, `PR`, `LABEL`, plus `[env]`), runs `paths_command` for the page map, launches `serve` on `--port`, and polls `health_url` until it responds.
4. Headless Chromium logs in (if `[auth]`) and screenshots every page at each `[viewports]` size × each `schemes` colour, full-page, after `networkidle`.
5. `--post` uploads each PNG via the undocumented `uploads.github.com/user-attachments/assets` endpoint (GitHub only accepts uploads to a repo you can push to — `upload_remote`, default `origin`, i.e. the fork) and writes them into the PR description between `<!-- pr-screenshots:start -->` and `<!-- pr-screenshots:end -->`. Re-running replaces that block only. An uploaded asset 404s until a description references it, which `--post` does immediately.

A page name missing from the resolved paths at a commit is skipped, so a brand-new page produces after shots only.

## Config reference (`pr-shots.toml`)

- `repo` — owner/name that owns the PRs (else `upstream`, else `origin`).
- `upload_remote` — remote used to upload images; must be pushable (default `origin`).
- `port`, `out_dir` — defaults 8299, `.pr-shots`.
- `prepare` — list of bash strings run in order in the worktree before serving: `npm ci`, `pip install`, `manage.py migrate`, seed scripts, frontend builds. Failure aborts.
- `serve` — foreground command that serves the app on `$PORT` (process group SIGTERMed after).
- `health_url` — URL to poll, `{port}` substituted (default `/`).
- `[paths]` — static `name = "/path"` map.
- `paths_command` — bash string run in the worktree after `prepare`; prints `{"name": "/path"}` JSON raw or as a `SHOTS_PATHS=<json>` line. Merges over `[paths]`.
- `default_pages`, `[per_pr]` — which page names to shoot (default: all resolved).
- `[auth]` — `url`, `username_field`, `password_field`, `submit`, `username`, `password`. Omit for public pages.
- `[viewports]` (name → `{width, height}`), `schemes` — capture matrix.
- `chromium` — path to a browser executable for `playwright.chromium.launch(executable_path=…)`; else `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`, else Playwright's own browsers (which must be installed already — do not run `playwright install`).
- `[env]` — extra env vars for every command. Literal strings, not shell-expanded.

## Per-stack examples

Django (the app this was written for — `scripts/pr_screenshots_seed.py` in this skill is a working `SHOTS_PATHS` seed for it):

```toml
[env]
SECRET = "pr-shots"
DJANGO_SETTINGS_MODULE = "local_serve"
prepare = [
  "printf 'from config.settings import *\\nIS_PROD = False\\n' > src/local_serve.py",
  "uv run --project $ROOT --no-sync python src/manage.py migrate --noinput",
  "uv run --project $ROOT --no-sync python src/manage.py shell < $ROOT/scripts/seed.py",
  "uv run --project $ROOT --no-sync python src/manage.py collectstatic --noinput",
]
serve = "cd src && uv run --project $ROOT --no-sync gunicorn --bind localhost:$PORT config.wsgi:application"
health_url = "http://localhost:{port}/health/"
paths_command = "uv run --project $ROOT --no-sync python $ROOT/scripts/resolve_routes.py"
```

Node / SPA:

```toml
prepare = ["npm ci", "npm run build"]
serve = "npm run preview -- --port $PORT"
health_url = "http://localhost:{port}/"
[paths]
home = "/"
```

Static site: `serve = "python -m http.server $PORT --directory dist"`, `[paths]` only, no `[auth]`.

Seeded-data apps: create a `shots`/`shots-pass-12345` user (matching `[auth]`) and the minimal objects each page needs in a seed script called from `prepare`, and have it (or a separate `paths_command`) print the routes to captured objects as JSON — routes that don't resolve on an old commit are skipped, which is exactly what you want for new pages.

## Limits

- The same `pr-shots.toml` is used for both commits (it's read from the main checkout). If the two commits need different build steps, write `prepare` commands that work on the worktree's own code, or point `--before-ref` at a compatible commit.
- Seeded/static data only — a change that depends on specific content or non-default settings needs a seed or prepare change to show up.
- Full-page screenshots after `networkidle`; hover states and open dialogs are not captured.
- Each PR takes ~1–3 min per side depending on `prepare`. Pass several PRs in one invocation.
- `gh` 2.99+ adds `gh pr edit --attach`, which could replace the upload code but needs write access to the PR's own repo.
