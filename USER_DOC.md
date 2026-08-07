# User documentation

## Services

The stack is three containers behind a single HTTPS entrypoint:

- **nginx** — the only container reachable from outside; terminates TLS on
  port 443 and is what your browser talks to.
- **wordpress** — runs WordPress and PHP-FPM; not reachable directly.
- **mariadb** — the WordPress database; not reachable directly.

## Prerequisites

- Docker + Docker Compose v2 (`docker compose`, not `docker-compose`).
- Port 443 free on the host.
- The domain in `srcs/.env` (`DOMAIN_NAME`) resolving to `127.0.0.1`. On
  Linux/macOS:

  ```sh
  echo "127.0.0.1  $(grep DOMAIN_NAME srcs/.env | cut -d= -f2)" | sudo tee -a /etc/hosts
  ```

## Configuration and credentials

Non-sensitive settings (domain, database name, usernames, emails) live in
`srcs/.env`. That file is **git-ignored** and must be created locally
before the first run — the repository deliberately contains no
configuration file that could accumulate credentials. Create it after
cloning with these keys:

```
DOMAIN_NAME=...
MYSQL_DATABASE=...
MYSQL_USER=...
WP_ADMIN_USER=...
WP_ADMIN_EMAIL=...
WP_NORMAL_USER=...
WP_NORMAL_EMAIL=...
```

Passwords are **not** in `.env`. Each one lives in its own file under
`secrets/` (git-ignored, mounted into the containers as Docker secrets),
which must be created locally before the first run:

```sh
mkdir -p secrets
printf '%s' 'your_root_password'   > secrets/db_root_password.txt
printf '%s' 'your_db_password'     > secrets/db_password.txt
printf '%s' 'your_admin_password'  > secrets/wp_admin_password.txt
printf '%s' 'your_author_password' > secrets/wp_user_password.txt
```

These are the credentials for both accounts created in WordPress
(`WP_ADMIN_USER` is the administrator, `WP_NORMAL_USER` a regular author)
and for the database. Keep the `secrets/` directory private — it is the
single place all of this stack's passwords live.

These values are only applied on the *first* boot against an empty data
directory — changing them later requires `make fclean` first (this wipes
the database and WordPress install).

## Running it

```sh
make          # same as `make up`: creates the data dirs, builds images, starts the stack
make ps       # check container status
make logs     # follow logs from all three containers
```

Then open `https://<DOMAIN_NAME>` in a browser. The certificate is
self-signed, so you'll need to accept the browser's security warning.

- **Website**: `https://<DOMAIN_NAME>`
- **Admin panel**: `https://<DOMAIN_NAME>/wp-admin`, log in with
  `WP_ADMIN_USER` and the password from `secrets/wp_admin_password.txt`.
- A second, non-admin author account is available with `WP_NORMAL_USER`
  and the password from `secrets/wp_user_password.txt`.

`make ps` should show all three containers as `Up`; `make logs` (or
`docker compose -f srcs/docker-compose.yml logs -f <service>`) is the way
to confirm a service actually finished starting (e.g. WordPress prints
"WordPress is already installed." once ready).

## Stopping / cleaning up

```sh
make stop     # stop containers, keep them and all data
make start    # resume stopped containers
make down     # stop and remove containers (data is untouched)
make clean    # down + remove images and named volumes
make fclean   # clean + wipe the persisted database and website files (irreversible)
make re       # fclean + up (full reset)
```

## Troubleshooting

- **Browser can't reach the site**: confirm `/etc/hosts` maps `DOMAIN_NAME`
  to `127.0.0.1` and that nothing else is bound to port 443.
- **"Not Secure" warning**: expected — the certificate is self-signed for
  local/evaluation use, not issued by a public CA.
- **Stuck on setup after editing `.env` or a secret file**: WordPress/
  MariaDB only apply `.env` and `secrets/` values on first install. Run
  `make fclean` to reset and reinstall from scratch.
- **`make fclean` can't remove files under the data directory as your own
  user**: if `$HOME` is an NFS-mounted home directory with `root_squash`
  enabled (common on 42 cluster machines and some VM setups), every write
  a container makes — including the `chown` to `www-data`/`mysql` at the
  end of each entrypoint script — gets remapped server-side to the
  anonymous `nfsnobody` user instead. Your own host user then has no write
  access to those files (check with
  `stat -c '%U:%G %a' $HOME/data/wordpress`; `nfsnobody:nfsnobody 755`
  confirms it). `make fclean` already works around this by deleting through
  a throwaway container instead of the host shell, since a container's root
  process gets root-squashed to `nfsnobody` the same way the files were
  created — and `nfsnobody` owns them, so the delete succeeds. If you ever
  need to clean up manually, do the same: `sudo rm -rf` (root also
  squashes to `nfsnobody`) rather than a plain `rm -rf` as yourself.