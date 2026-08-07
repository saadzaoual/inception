*This project has been created as part of the 42 curriculum by szaoual.*

# Inception

## Description

Inception sets up a small, self-contained web infrastructure using Docker:
a WordPress site, served over TLS, backed by its own database — with every
image built from scratch (no images pulled from Docker Hub other than the
Debian base). The goal is to practice container orchestration, isolation,
and persistence: each service (nginx, WordPress+php-fpm, MariaDB) runs in
its own container, on its own dedicated network, with its data kept outside
the containers' lifecycle.

## Instructions

**Prerequisites**: Docker, Docker Compose v2, port 443 free on the host,
and `<DOMAIN_NAME>` (see `srcs/.env`) resolving to `127.0.0.1` (add it to
`/etc/hosts`).

**First run after cloning.** Neither the configuration file nor the
passwords are tracked in git, so both have to be created locally:

```sh
cp srcs/.env.example srcs/.env          # configuration (no passwords)

mkdir -p secrets                        # one password per file
printf '%s' 'db_root_pw' > secrets/db_root_password.txt
printf '%s' 'db_pw'      > secrets/db_password.txt
printf '%s' 'wp_admin_pw'> secrets/wp_admin_password.txt
printf '%s' 'wp_user_pw' > secrets/wp_user_password.txt
chmod 600 secrets/*.txt
```

```sh
make          # build every image and start the stack
make down     # stop and remove the containers
make clean    # down + remove images and named volumes
make fclean   # clean + wipe persisted data
make re       # fclean + up (full reset)
```

Then open `https://<DOMAIN_NAME>` in a browser (the certificate is
self-signed — accept the warning).

Full usage details are in [USER_DOC.md](USER_DOC.md); the technical
breakdown of each container is in [DEV_DOC.md](DEV_DOC.md).

## Resources

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- [WP-CLI documentation](https://wp-cli.org/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [nginx documentation](https://nginx.org/en/docs/)
- [Debian release information](https://www.debian.org/releases/)

**AI usage**: an AI assistant (Claude Code) was used throughout this
project. Specifically, it helped to:

- scaffold the Dockerfiles and container entrypoint scripts;
- diagnose and repair a broken local git repository (object files left
  with incorrect ownership after a container ran as root against an
  NFS-mounted working directory);
- audit the repository for committed credentials, then purge
  `secrets/*.txt` and `srcs/.env` from the entire git history with
  `git filter-repo` and rotate the exposed database passwords;
- move the three images from `debian:bullseye` to `debian:bookworm` (the
  penultimate stable release) and migrate WordPress from PHP 7.4 to
  PHP 8.2 accordingly;
- rewrite the MariaDB entrypoint so provisioning runs through
  `mariadbd --init-file` instead of backgrounding a temporary daemon —
  the container's PID 1 is the real server, with nothing running in the
  background and no polling loop;
- review the setup against this subject's requirements and correct the
  gaps found (folder naming, the data volume host path, explicit image
  names and tags, and this README's structure).

Each change was reviewed against the subject text before being applied,
and the running stack was re-verified afterwards.

## Project description

**Docker usage and sources**: three custom images are built from
`debian:bookworm` (the penultimate stable Debian release), one per service,
defined in `srcs/docker-compose.yml` and built from
`srcs/requirements/<service>/Dockerfile`. `nginx` is the sole entrypoint
into the stack (port 443, TLSv1.2/1.3 only); `wordpress` runs php-fpm with
no bundled web server; `mariadb` runs standalone. All three share a single
bridge network (`inception`) and restart automatically on crash.

- **Virtual Machines vs Docker**: a VM virtualizes an entire machine,
  including its own kernel, which makes it heavier to boot and to
  duplicate per service. Containers share the host kernel and only
  isolate the process/filesystem/network namespace, so three containers
  here start in seconds and cost a fraction of the resources three VMs
  would — at the cost of weaker isolation than a true VM boundary.
- **Secrets vs Environment variables**: environment variables passed via
  `env_file:` are readable by anything with access to the container's
  environment (e.g. `docker inspect`), so they are a poor fit for
  credentials. This project splits the two: non-sensitive configuration
  (domain, database name, usernames, emails) flows through `srcs/.env`,
  while every password lives in a git-ignored file under `secrets/`,
  declared in the compose file's `secrets:` block and mounted as a file
  under `/run/secrets/` inside only the containers that declare it — out
  of `docker inspect`, out of process listings, and out of the repository.
- **Docker Network vs Host Network**: `network: host` would drop container
  network isolation entirely, exposing every container port directly on
  the host and risking port collisions — and it's disallowed by the
  subject. The custom bridge network used here keeps containers isolated,
  resolves peers by service name (e.g. `wordpress` reaching `mariadb`),
  and only forwards the one port (443, on `nginx`) that's meant to be
  public.
- **Docker Volumes vs Bind Mounts**: a plain bind mount ties a container
  path directly to an arbitrary host path, bypassing Docker's volume
  management. This project uses Docker **named volumes** (`mariadb_data`,
  `wordpress_data`) — as the subject requires — configured with a `local`
  driver and `bind` driver options so they still resolve to a fixed host
  path (`/home/szaoual/data/...`), combining Docker-managed volume
  semantics with a predictable, inspectable location on disk.