# Developer documentation

## Setup from scratch

Prerequisites: Docker + Docker Compose v2, and a host user whose `$HOME`
is writable (the data volumes bind under `$HOME/data`).

1. Clone the repo.
2. Create the four password files under `secrets/` (git-ignored — see
   `.gitignore`): `db_root_password.txt`, `db_password.txt`,
   `wp_admin_password.txt`, `wp_user_password.txt` — one password per
   file, no trailing newline.
3. Create `srcs/.env` (git-ignored) from the tracked template:
   `cp srcs/.env.example srcs/.env`, then adjust the domain, database
   name, usernames and emails — see the table under **Environment
   variables** for the full list of keys. It holds no credentials, but it
   is kept out of git so that no committed file can accumulate them by
   accident.
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

Plain `mariadb-server` installed via apt. `tools/setup.sh` is the container
entrypoint and does first-boot setup on every start:

1. Creates `/run/mysqld` and gives it to the `mysql` user.
2. Runs `mysql_install_db` only if `/var/lib/mysql/mysql` doesn't exist yet
   (i.e. first run against an empty volume).
3. Writes the provisioning SQL to `/run/mysqld/init.sql` (mode `600`),
   reading the passwords from `/run/secrets/` and the database/user names
   from `.env`.
4. `exec`s `mariadbd --user=mysql --init-file=/run/mysqld/init.sql` in the
   foreground.

`--init-file` is the key detail: `mariadbd` runs that SQL itself, once the
server is up and the grant tables are live, before accepting connections.
So the container never has to background a temporary daemon or poll for
readiness — PID 1 is the real server from the first instruction, which is
what makes signals (`docker stop`) and `restart:` behave correctly.
(`mysqld_safe` is deliberately avoided for the same reason: it's a shell
wrapper that supervises the daemon and doesn't forward signals.)

`--bootstrap` would look like the natural fit here and is **not** usable:
it implies `--skip-grant-tables`, so `CREATE USER` and `GRANT` fail inside
it with `ERROR 1290`.

Every statement in the init file is idempotent (`CREATE DATABASE IF NOT
EXISTS`, `CREATE USER IF NOT EXISTS`, `GRANT`, `ALTER USER`), so it is safe
to re-run on every boot — and a half-provisioned database repairs itself on
the next start rather than being skipped forever. The file is written under
`/run` (container-local, gone with the container) and never under
`/var/lib/mysql`, which is bind-mounted to the host: the passwords must not
land on the host filesystem.

Anonymous accounts are removed with `DELETE FROM mysql.global_priv WHERE
User=''`. `mysql.user` is a read-only view in MariaDB 10.4+, so deleting
from it there fails; `global_priv` is the real underlying table.

`conf/50-server.cnf` sets `bind-address = 0.0.0.0` — required since the
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

`tools/setup.sh` is the entrypoint: it generates a self-signed certificate
into `/etc/nginx/ssl/` with `openssl` — at container start, so the cert is
never baked into the image or committed — then `exec`s
`nginx -g "daemon off;"` so PID 1 is nginx itself. The certificate's CN
comes from `${DOMAIN_NAME}`.

`conf/nginx.conf` restricts the server to `ssl_protocols TLSv1.2 TLSv1.3`
per the subject's constraints, listens on 443 only (no port 80 is exposed
anywhere in the stack), proxies any `*.php` request to `wordpress:9000` via
FastCGI, and serves everything else as a static file from the shared
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

`srcs/.env` (git-ignored, no credentials):

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

`/home/szaoual/data/mariadb` and `/home/szaoual/data/wordpress` on the host
back the `mariadb_data`/`wordpress_data` named volumes — they persist
across `make down`/`make up` and live outside the repository entirely, so
they are never tracked in git. The Makefile hardcodes that absolute path
rather than using `$(HOME)`, so that running `sudo make` cannot resolve it
to `/root/data` and silently diverge from the `device:` paths in
`docker-compose.yml`. `make fclean` empties them; `make clean` also removes the built
images and named volumes but leaves the host directories in place for
`fclean` to clear.