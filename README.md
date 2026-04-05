# pgbackup v2 — PostgreSQL Backup CLI (pgBackRest Edition)

Install **once** per server. Use for **any number of projects** via `--config`.  
Powered by [pgBackRest](https://pgbackrest.org) — battle-tested, used in production at scale.

---

## What you get over the scratch-built v1

| Feature | v1 (pg_basebackup) | v2 (pgBackRest) |
|---|---|---|
| Full backups | ✅ | ✅ |
| Differential backups | ❌ | ✅ |
| Incremental backups | ❌ | ✅ Block-level |
| WAL archiving | ✅ gzip | ✅ Parallel, compressed |
| S3 / GCS storage | ❌ | ✅ Native |
| Encryption | ❌ | ✅ AES-256 |
| Parallel backup/restore | ❌ | ✅ Configurable threads |
| Delta restore | ❌ | ✅ Only changed blocks |
| Repo integrity verify | ❌ | ✅ `pgbackup verify` |
| Resume interrupted backup | ❌ | ✅ |

---

## Install (once per server)

### Step 1 — Install pgBackRest

```bash
# Ubuntu / Debian
sudo apt install pgbackrest

# RHEL / Rocky / AlmaLinux
sudo dnf install pgbackrest
```

### Step 2 — Install pgbackup CLI

```bash
tar -xzf pgbackup-2.0.0.tar.gz
cd pgbackup-2.0.0
sudo ./install.sh
```

---

## Add a New Project (5 minutes)

```bash
# 1. Generate config
pgbackup init --project myapp --output /etc/pgbackup/myapp.env

# 2. Edit — set PG_HOST, PG_DATABASE, REPO_PATH or S3 details
nano /etc/pgbackup/myapp.env

# 3. See what to add to postgresql.conf
pgbackup wal-setup --config /etc/pgbackup/myapp.env

# 4. Add those lines to postgresql.conf, then reload
psql -c "SELECT pg_reload_conf();"

# 5. Initialise pgBackRest stanza for this project
sudo pgbackup setup --config /etc/pgbackup/myapp.env

# 6. Enable automated scheduling
sudo pgbackup enable --config /etc/pgbackup/myapp.env

# 7. First backup + verify
sudo -u postgres pgbackup backup --config /etc/pgbackup/myapp.env
pgbackup status --config /etc/pgbackup/myapp.env
pgbackup check  --config /etc/pgbackup/myapp.env
```

**For project #2 — repeat steps 1–7 with a different name. That's it.**

---

## All Commands

```bash
pgbackup init      --project <name> --output /etc/pgbackup/<name>.env
pgbackup setup     --config /etc/pgbackup/<name>.env        # once per project
pgbackup wal-setup --config /etc/pgbackup/<name>.env        # print postgresql.conf lines
pgbackup backup    --config /etc/pgbackup/<name>.env [--type full|diff|incr]
pgbackup restore   --config /etc/pgbackup/<name>.env --target-dir /path/to/restore
pgbackup restore   --config /etc/pgbackup/<name>.env --target-dir /path --pitr "2024-01-15 14:30:00+00"
pgbackup restore   --config /etc/pgbackup/<name>.env --target-dir /path --delta   # fast in-place
pgbackup check     --config /etc/pgbackup/<name>.env
pgbackup status    --config /etc/pgbackup/<name>.env
pgbackup verify    --config /etc/pgbackup/<name>.env
pgbackup enable    --config /etc/pgbackup/<name>.env        # sudo
pgbackup disable   --config /etc/pgbackup/<name>.env        # sudo
```

---

## Backup Schedule (auto-configured by `pgbackup enable`)

```
02:00 AM  → full backup    (daily)
12:00 PM  → diff backup    (daily, changes since last full)
Every 6h  → health check   (alerts on issues)
Continuous → WAL archiving  (per segment, max 5 min data loss)
```

---

## Using S3 Storage

In your project `.env`:

```bash
REPO_TYPE="s3"
REPO_S3_BUCKET="my-pg-backups"
REPO_S3_REGION="ap-south-1"
# Leave key/secret blank to use IAM instance role (recommended)
REPO_S3_KEY=""
REPO_S3_KEY_SECRET=""
```

Then run `pgbackup setup` — pgBackRest handles the rest.

---

## Encryption

```bash
ENCRYPT_ENABLED=true
ENCRYPT_PASSPHRASE="long-random-string-store-this-safely"
```

AES-256-CBC. Store the passphrase in a secrets manager — without it, backups cannot be restored.

---

## Recovery Examples

```bash
# Restore to latest
pgbackup restore --config /etc/pgbackup/myapp.env \
                 --target-dir /var/lib/postgresql/16/recovered

# Restore to specific time
pgbackup restore --config /etc/pgbackup/myapp.env \
                 --target-dir /var/lib/postgresql/16/recovered \
                 --pitr "2024-01-15 14:30:00+00"

# Delta restore — only restore changed blocks (much faster for large DBs)
pgbackup restore --config /etc/pgbackup/myapp.env \
                 --target-dir /var/lib/postgresql/16/main \
                 --delta

# After restore, start PostgreSQL:
pg_ctl -D /var/lib/postgresql/16/recovered start
# It will replay WAL and promote automatically.
```

---

## PostgreSQL in Docker

See `docker/docker-compose.yml`. The pgBackRest binary and config are bind-mounted into the container so `archive_command` can call it directly. The repository directory is also shared via volume mount.

This example is intended to run from Linux or WSL2 Ubuntu, not directly from native Windows PowerShell.

```bash
# One-time setup for Docker host
sudo ./docker/setup-docker-host.sh --project myapp

# Set a real password for the postgres container
nano docker/secrets/pg_password.txt

docker compose up -d
sudo pgbackup setup  --config /etc/pgbackup/myapp.env
sudo pgbackup enable --config /etc/pgbackup/myapp.env
```

If your WSL image has the older standalone Compose binary, replace `docker compose` with `docker-compose`.

### WSL2 Smoke Test

This is the fastest trust-building path on a Windows machine:

```bash
# inside WSL2 Ubuntu
sudo apt update
sudo apt install -y postgresql-client pgbackrest docker.io docker-compose
sudo ./install.sh
sudo ./docker/setup-docker-host.sh --project myapp
nano docker/secrets/pg_password.txt
pgbackup init --project myapp --output /etc/pgbackup/myapp.env
nano /etc/pgbackup/myapp.env
./docker/smoke-test.sh
```

Recommended config values for the Docker smoke test:

```bash
PG_HOST="127.0.0.1"
PG_PORT="5432"
PG_USER="postgres"
PG_DATABASE="myapp_production"
PG_DATA_DIR="/var/lib/postgresql/data"
REPO_TYPE="posix"
REPO_PATH="/var/backups/pgbackrest/${PROJECT_NAME}"
```

What the smoke test does:

1. Starts the PostgreSQL Docker container.
2. Waits for PostgreSQL to accept connections.
3. Writes sample data.
4. Runs `pgbackup setup`.
5. Runs a full backup.
6. Runs `pgbackup check`.
7. Restores into `/tmp/<project>-restore`.

If all of that works, you have validated the most important trust path: connect, backup, verify, and restore.

The bundled Docker `pg_hba.conf` trusts localhost-only connections for smoke testing. Do not use that exact authentication policy unchanged for production.

---

## File Layout After Install

```
/usr/local/bin/pgbackup               ← CLI (in PATH)
/usr/local/lib/pgbackup/              ← core scripts
/usr/local/share/pgbackup/templates/  ← config template
/etc/pgbackup/                        ← project configs (one .env each)
/etc/pgbackrest/                      ← generated pgBackRest configs (auto)
```
