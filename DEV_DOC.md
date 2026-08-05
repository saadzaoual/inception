# Developer documentation

## Setup from scratch

Prerequisites: Docker + Docker Compose v2, and a host user whose `$HOME`
is writable (the data volumes bind under `$HOME/data`).

1. Clone the repo.
2. Create the four password files under `secrets/` (git-ignored — see
   `.gitignore`): `db_root_password.txt`, `db_password.txt`,
   `wp_admin_password.txt`, `wp_user_password.txt` — one password per
   file, no trailing newline.
3. Adjust `srcs/.env` (tracked — contains no credentials) if the domain,
   database name, usernames or emails need to change.
4. `make` builds every image and starts the stack (see **Commands**).

## Architecture

Three services on one bridge network (`inception`), each built from
`debian:bookworm` (the penultimate stable Debian release) — no Docker Hub
images for nginx/wordpress/mariadb themselves:

```
client ──443/TLS──> nginx ──9000/FastCGI──> wordpress ──3306──> mariadb
                                                  │                 │
                                          wordpress_data       mariadb_data
                                       (named volume,        (named volume,
                                     bind-backed on host)   bind-backed on host)
```

Only `nginx` publishes a port to the host. `nginx` and `wordpress` share the
`wordpress_data` volume: nginx needs it to serve static assets directly,
wordpress needs it as PHP-FPM's working directory.

Volumes are declared in `srcs/docker-compose.yml` as Docker **named
volumes** (`mariadb_data`, `wordpress_data`) using the `local` driver with
`driver_opts: o: bind` — that keeps them addressable by name (as the
subject requires) while still resolving to a fixed, inspectable path on the
host: `/home/szaoual/data/mariadb` and `/home/szaoual/data/wordpress`. That
path is login-specific — cloning this repo under a different account
requires editing `device:` in `docker-compose.yml` to match.

Each service's image is explicitly named and tagged (`mariadb:inception`,
`wordpress:inception`, `nginx:inception`) via `image:` in the compose file,
so the image name matches its service and never resolves to `latest`.

## Services

### mariadb (`srcs/requirements/mariadb/`)

Plain `mariadb-server` installed via apt. `tools/init.sh` is the container
entrypoint and does first-boot setup on every start:

1. Reads the root and app-user passwords from `/run/secrets/`.
2. `chown`s `/var/lib/mysql` to the `mysql` user (the volume can come in
   with host ownership).
3. Runs `mysql_install_db` only if `/var/lib/mysql/mysql` doesn't exist yet
   (i.e. first run against an empty volume).
4. Starts a temporary `mysqld --skip-networking` in the background (socket
   only — nothing can connect over the network before the passwords are
   set) and polls `mysqladmin ping` until it responds.
5. Applies the setup SQL (create DB, create app user, set root password) —
   names from `.env`, passwords from the secrets — idempotent via
   `CREATE ... IF NOT EXISTS`.
6. Shuts the temporary server down, waits for it to exit, and `exec`s
   `mysqld --user=mysql` in the foreground, so PID 1 is the actual server
   process (`mysqld_safe` is deliberately avoided: it's a shell wrapper
   that supervises/respawns the daemon and doesn't forward signals).

Step 6's shutdown/restart exists so the container's real PID 1 is `mysqld`,
not a detached background job — needed for signals (`docker stop`) and
`restart: always` to work correctly.

`conf/50-server.cnf` sets `bind_address = 0.0.0.0` — required since the
client connects from a different container on the bridge network, not
`localhost`.

### wordpress (`srcs/requirements/wordpress/`)

Installs `php8.2-fpm` + `wp-cli`, no HTTP server (nginx handles that).
`conf/www.conf` puts PHP-FPM's pool on `0.0.0.0:9000` (TCP, not the default
unix socket) so nginx can reach it by container name.

`tools/init.sh`:

1. Busy-waits on a `mariadb` connection before doing anything else — mariadb
   and wordpress start concurrently, `depends_on` only orders container
   *start*, not service readiness.
2. If `wp-config.php` doesn't exist (first run / fresh volume): downloads
   WordPress core, writes `wp-config.php`, runs `wp core install`, and
   creates a second, non-admin user — all via `wp-cli`, names/emails from
   `.env` and passwords from `/run/secrets/`.
3. Fixes ownership to `www-data` and `exec`s `php-fpm8.2 -F` (foreground) as
   PID 1.

The "install only if `wp-config.php` is missing" check is what makes
restarts idempotent — on subsequent boots it skips straight to serving.

### nginx (`srcs/requirements/nginx/`)

Self-signed cert generated **at build time** in the `Dockerfile` (not at
runtime), valid for TLSv1.2/TLSv1.3 only, per the subject's constraints.
`conf/nginx.conf` proxies any `*.php` request to `wordpress:9000` via
FastCGI; everything else is served as a static file from the shared
`wordpress_data` volume.

## Known gaps

- The bind-backed `device:` paths in `docker-compose.yml` are hardcoded to
  one host login — not portable across machines/users without editing them.
- If `$HOME` is NFS-mounted with `root_squash` (true here), every write a
  container makes under `$HOME/data` — including the `chown` at the end of
  each entrypoint script — lands owned by the anonymous `nfsnobody` user
  instead of the intended in-container user. That's harmless for the
  containers themselves (they run as root/re-chown on every boot), but it
  means the host user can't `rm` that data directly; `fclean` deletes it
  through a throwaway container instead (see the Makefile).

## Environment variables (`srcs/.env`) and secrets

`srcs/.env` (tracked in git, no credentials):

| Var | Used by |
|---|---|
| `DOMAIN_NAME` | nginx `server_name` (via `/etc/hosts` on the host), `wp core install --url` |
| `MYSQL_DATABASE`, `MYSQL_USER` | mariadb init, wordpress DB config |
| `WP_ADMIN_USER`, `WP_ADMIN_EMAIL` | WordPress admin account |
| `WP_NORMAL_USER`, `WP_NORMAL_EMAIL` | second WordPress (author) account |

Passwords are Docker secrets: each file under `secrets/` (git-ignored) is
declared in the compose file's top-level `secrets:` block and mounted at
`/run/secrets/<name>` inside only the services that list it:

| Secret file | Mounted in | Purpose |
|---|---|---|
| `db_root_password.txt` | mariadb | MariaDB root password |
| `db_password.txt` | mariadb, wordpress | WordPress DB user password |
| `wp_admin_password.txt` | wordpress | WordPress admin account password |
| `wp_user_password.txt` | wordpress | WordPress author account password |

## Commands (Makefile / Docker Compose)

```sh
make            # prepare data dirs, build every image, start the stack
make ps          # container status
make logs        # follow logs from all three containers
make down         # stop and remove containers (volumes untouched)
make clean        # down + remove built images and named volumes
make fclean       # clean + wipe the host data directories
make re           # fclean + up (full reset)
```

Equivalent raw compose commands (run from the repo root):
`docker compose -f srcs/docker-compose.yml <up -d --build|down|ps|logs -f>`.

## Data / volumes

`$HOME/data/mariadb` and `$HOME/data/wordpress` on the host back the
`mariadb_data`/`wordpress_data` named volumes — they persist across
`make down`/`make up` and are **not** tracked in git (`data/` is
git-ignored as an extra safety net, in case it's ever created inside the
repo). `make fclean` empties them; `make clean` also removes the built
images and named volumes but leaves the host directories in place for
`fclean` to clear.